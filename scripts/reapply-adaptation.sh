#!/usr/bin/env bash
#
# reapply-adaptation.sh -- replay the "de-google3" adaptation layer on top of a
# raw webaoa/ snapshot copied from platform/tools/multitest_transport.
#
# Background
# ----------
# Branch `explore-pristine-baseline` keeps webaoa/ as a *raw* upstream snapshot
# plus a thin, deliberately separable adaptation layer that makes it build with
# the public Angular CLI + npm toolchain instead of google3's Bazel and the
# internal angular_components package:
#
#   explore-pristine-baseline  ==  raw upstream snapshot
#                                  + this adaptation layer (commit 90f6892)
#
# 90f6892 ("Re-adapt refreshed webaoa/ for standalone Angular CLI build")
# derived that layer by hand. This script is the same work as a replayable
# procedure, so the next refresh (44f9b9e's role) does not have to re-derive it
# file by file.
#
# Usage
# -----
#   # 1) refresh the snapshot -- raw, no adaptation
#   git checkout explore-pristine-baseline
#   UPSTREAM=/home/hunt/multitest_transport/multitest_transport/tools/webaoa
#   rm -rf webaoa && cp -r "$UPSTREAM" webaoa
#   git add -A && git commit -m "webaoa: refresh from multitest_transport (raw snapshot)"
#
#   # 2) replay the adaptation layer
#   ./scripts/reapply-adaptation.sh
#   npm run build && npm test
#   git add -A && git commit -m "Re-adapt refreshed webaoa/ for standalone Angular CLI build"
#
#   # rehearsal without touching the repo (see VALIDATION below):
#   WEBAOA_DIR=/tmp/adapt-test/webaoa ./scripts/reapply-adaptation.sh
#
# The script is idempotent: running it against an already-adapted tree changes
# nothing. It only rewrites files whose content actually changes, so it is safe
# to re-run after a partial refresh too.
#
# Environment overrides
# ---------------------
#   WEBAOA_DIR    target webaoa/ tree      (default: <repo>/webaoa)
#   ADAPT_DIR     canonical local-only files (default: <repo>/scripts/adaptation)
#   UPSTREAM_DIR  optional raw upstream copy; when set, the script prints the
#                 resulting adaptation surface (files that still differ from
#                 upstream) so you can eyeball whether upstream introduced
#                 something the layer does not yet cover.
#
# Exit status: 0 on success, 1 on a usage/precondition error.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBAOA_DIR="${WEBAOA_DIR:-$REPO_ROOT/webaoa}"
ADAPT_DIR="${ADAPT_DIR:-$REPO_ROOT/scripts/adaptation}"
UPSTREAM_DIR="${UPSTREAM_DIR:-}"

step() { printf '\n== %s\n' "$*"; }
log()  { printf '   %s\n' "$*"; }

# ---------------------------------------------------------------- preconditions
[[ -d "$WEBAOA_DIR" ]] || { echo "error: no such directory: $WEBAOA_DIR" >&2; exit 1; }
[[ -f "$WEBAOA_DIR/app.ts" ]] || {
  echo "error: $WEBAOA_DIR does not look like a webaoa/ tree (no app.ts)" >&2
  exit 1
}
[[ -d "$ADAPT_DIR" ]] || { echo "error: no such directory: $ADAPT_DIR" >&2; exit 1; }

step "adapting $WEBAOA_DIR"

# ------------------------------------------------- 1. local-only canonical files
# Upstream has neither of these; both are copied verbatim from the layer that
# was proven to build on master.
copy_if_different() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    log "unchanged  ${dst#"$WEBAOA_DIR"/}"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    log "wrote      ${dst#"$WEBAOA_DIR"/}"
  fi
}

copy_if_different "$ADAPT_DIR/webaoa-tsconfig.json" "$WEBAOA_DIR/tsconfig.json"
copy_if_different "$ADAPT_DIR/jasmine_util.ts" "$WEBAOA_DIR/testing/jasmine_util.ts"

# ------------------------------------------------------- 2. in-place rewrites
perl - "$WEBAOA_DIR" <<'PERL'
use strict;
use warnings;

my $dir = shift @ARGV;
my (@touched, @already, @missing);

sub slurp {
  my ($path) = @_;
  open my $fh, '<', $path or die "$path: $!";
  local $/;
  my $c = <$fh>;
  close $fh;
  return $c;
}

sub spew {
  my ($path, $c) = @_;
  open my $fh, '>', $path or die "$path: $!";
  print {$fh} $c;
  close $fh;
}

# Apply a coderef to a file's contents; record the file only if it changed.
sub transform {
  my ($path, $code) = @_;
  if (!-f $path) { push @missing, $path; return; }
  my $before = slurp($path);
  my $after  = $before;
  $code->(\$after);
  if ($after ne $before) { spew($path, $after); push @touched, $path; }
  else                   { push @already, $path; }
}

# --- 2.1 app.ts: restore the w3c-web-usb triple-slash reference --------------
# tsconfig.app.json sets "types": [], so ambient declarations are program-wide
# and this reference is the *only* source of USBDevice/navigator.usb for the
# whole app compilation.
transform("$dir/app.ts", sub {
  my ($c) = @_;
  return if $$c =~ m{reference types="w3c-web-usb"};
  $$c =~ s/\n\n(import )/\n\n\/\/\/ <reference types="w3c-web-usb" \/>\n\n$1/;
});

# --- 2.2 component decorators: .css -> .scss, Eager -> Default --------------
# google3's Bazel Sass rules emit the .css these styleUrls point at; this repo
# compiles .scss directly. ChangeDetectionStrategy.Eager does not exist in
# public Angular (only OnPush/Default). standalone: false is real public API
# and is kept as-is.
for my $f (qw(
  app.ts
  device/device_list.ts
  device/find_device_dialog.ts
  editor/action_editor.ts
  editor/touch_screen.ts
  editor/workflow_editor.ts
)) {
  my $p = "$dir/$f";
  if (!-f $p) { push @missing, $p; next; }
  transform($p, sub {
    my ($c) = @_;
    $$c =~ s{styleUrls: \['\./([\w.-]+)\.css'\]}{styleUrls: ['./$1.scss']}g;
    $$c =~ s{changeDetection: ChangeDetectionStrategy\.Eager,standalone: false,}
           {changeDetection: ChangeDetectionStrategy.Default,\n  standalone: false,}g;
  });
}

# --- 2.3 app_module.ts: keep provideAnimationsAsync() -----------------------
# google3 swaps zone.js for provideZoneChangeDetection(), which only works with
# bootstrapApplication(). This app boots via bootstrapModule() in main.ts; the
# swap was verified in a real browser to throw NG0207.
transform("$dir/app_module.ts", sub {
  my ($c) = @_;
  $$c =~ s{import \{NgModule, provideZoneChangeDetection\} from '\@angular/core';}
         {import {NgModule} from '\@angular/core';};
  $$c =~ s{providers: \[provideZoneChangeDetection\(\)\],}
         {providers: [provideAnimationsAsync()],};
  if ($$c !~ m{provideAnimationsAsync\} from '\@angular/platform-browser/animations/async'}) {
    $$c =~ s{(import \{BrowserAnimationsModule\} from '\@angular/platform-browser/animations';\n)}
           {$1import {provideAnimationsAsync} from '\@angular/platform-browser/animations/async';\n};
  }
});

# --- 2.4 *.scss: google3 material paths/API -> npm @angular/material --------
# Maps google3's newer Material Sass API back to what this project's pinned
# @angular/material 17.3.3 ships, and drops the `deprecated` module whose
# all-legacy-component-* mixins do not exist in that version.
for my $f (glob("$dir/*.scss $dir/*/*.scss")) {
  transform($f, sub {
    my ($c) = @_;
    $$c =~ s{^\@use 'third_party/javascript/angular_components/deprecated' as mat-deprecated;\n}{}m;
    $$c =~ s{\@use 'third_party/javascript/angular_components/material' as mat;}
           {\@use '\@angular/material' as mat;}g;
    $$c =~ s{^\@include mat-deprecated\.all-legacy-component-typographies\(\);\n}{}m;
    $$c =~ s{^\@include mat-deprecated\.all-legacy-component-themes\(\$theme\);\n}{}m;
    $$c =~ s{\@include mat\.app-background\(\);\n\@include mat\.elevation-classes\(\);}
           {\@include mat.core();}g;
    $$c =~ s{\bmat\.m2-define-}{mat.define-}g;
    $$c =~ s{mat\.\$m2-(grey|blue)-palette}{mat.\$$1-palette}g;
    $$c =~ s{mat-deprecated\.define-legacy-typography-config}{mat.define-legacy-typography-config}g;
    $$c =~ s{^(\@include mat\.deprecated-)}{// $1}mg;
    $$c =~ s{url\(/webaoa/static/}{url(/}g;
  });
}

# --- 2.5 index.html: Flask/ATS paths -> standalone-servable paths -----------
transform("$dir/index.html", sub {
  my ($c) = @_;
  $$c =~ s{^[ \t]*<link rel="stylesheet" href="/webaoa/static/styles\.css">\n}{}m;
  $$c =~ s{<link rel="shortcut icon" href="/webaoa/static/favicon\.ico">}
         {<link rel="shortcut icon" href="favicon.ico">}g;
  $$c =~ s{^[ \t]*<script src="/webaoa/app\.js"></script>\n}{}m;
});

# --- 2.6 *_test.ts: google3-internal jasmine_util -> local ./testing -------
for my $f (glob("$dir/*_test.ts $dir/*/*_test.ts")) {
  (my $relpath = $f) =~ s{^\Q$dir\E/}{};
  my $depth = ($relpath =~ tr{/}{});   # directory levels below webaoa/
  my $prefix = $depth == 0 ? './' : ('../' x $depth);
  transform($f, sub {
    my ($c) = @_;
    $$c =~ s{google3/third_party/py/multitest_transport/ui2/app/testing/jasmine_util}
           {$prefix . 'testing/jasmine_util'}ge;
  });
}

# ------------------------------------------------------------------- report
my (%seen, @unique);
for my $p (@touched) { next if $seen{$p}++; push @unique, $p; }
for my $p (@unique)   { printf("   rewrote   %s\n", $p); }
for my $p (@missing)  { printf("   MISSING   %s  <- upstream layout changed?\n", $p); }
printf("   (%d file(s) rewritten, %d already conforming)\n",
       scalar @unique, scalar @already);
exit(scalar(@missing) ? 2 : 0);
PERL

step "done"

# ------------------------------------------------------------- 3. the check
if [[ -n "$UPSTREAM_DIR" && -d "$UPSTREAM_DIR" ]]; then
  step "adaptation surface: files that still differ from upstream"
  log "expected: the de-google3 glue below; anything NEW here means upstream"
  log "changed something the layer does not cover yet -- review it by hand."
  diff -rq "$UPSTREAM_DIR" "$WEBAOA_DIR" || true
fi

step "next"
log "npm run build && npm test"
log "then commit the adaptation as its own commit"
