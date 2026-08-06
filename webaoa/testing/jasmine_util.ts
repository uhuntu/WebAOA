/**
 * @license
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {DebugElement} from '@angular/core';
import {By} from '@angular/platform-browser';

/** Returns the first element matching a CSS selector, or throws if none exist. */
export function getEl<T extends Element = HTMLElement>(
    root: DebugElement, selector: string): T {
  const found = root.query(By.css(selector));
  if (!found) {
    throw new Error(`No element found for selector '${selector}'`);
  }
  return found.nativeElement as T;
}

/** Returns all elements matching a CSS selector. */
export function getEls<T extends Element = HTMLElement>(
    root: DebugElement, selector: string): T[] {
  return root.queryAll(By.css(selector)).map(el => el.nativeElement as T);
}

/** Returns true if an element matching a CSS selector exists. */
export function hasEl(root: DebugElement, selector: string): boolean {
  return root.query(By.css(selector)) !== null;
}
