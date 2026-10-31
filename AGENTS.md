# Agent Guidelines for JellyBoi

These instructions guide AI agents working in this codebase. Always adhere strictly to these principles before and while making code changes.

---

## 1. UI Modification Scope Rule
- **Targeted UI Changes Only**: If asked to modify, redesign, tweak, or fix a UI element or feature, **only modify the UI code directly related to that task**.
- **No Unsolicited Cascading Changes**: Do not touch ViewModels, data queries, networking layer, or unrelated views unless explicitly requested or strictly required to make the UI work.
- **Keep Diffs Minimal**: Ensure that changes are localized to the specific view or component in question.

---

## 2. Refactoring & Code Replacement Rules
- **No Compatibility Bloat**: When refactoring, **do not** care about backward compatibility with superseded code.
- **No `typealias` or Wrapper Shims**: Do not introduce `typealias` bridges, compatibility wrappers, or deprecated adapter layers for old components.
- **Direct Replacement**: When a component, struct, class, or method is refactored or replaced, **directly replace the old implementation and update all call sites**. Cleanly delete the obsolete code.

---

## 3. Architecture & Code Style Guidelines
- **Architecture**: SwiftUI + MVVM. Keep view logic separate from business and data management logic.
- **Swift Concurrency**: Prefer Swift `async`/`await` and structured concurrency. **Do NOT use `Combine`**.
- **State Management**: Use `@State private var` for view-local state, `@Binding` for two-way parent-child data flow, and `let` for immutable view properties.
- **Type Safety**: Leverage Swift's strong type system. **Avoid force unwrapping (`!`)**; always safely unwrap with `guard let`, `if let`, or nil-coalescing (`??`).
- **Formatting**:
  - 4-space indentation.
  - PascalCase for types (structs, classes, enums, protocols).
  - camelCase for properties, methods, and variables.
  - Clean method separation and descriptive comments for non-obvious logic.

---

## 4. Pre-Coding Checklist
Before writing or generating new code:
1. **Search Existing Helpers**: Check [`JellyBoi/views/helper/`](file:///Users/garrettbutchko/Documents/Projects/Apps/iOS/Jellyboi%20All/JellyBoi/JellyBoi/views/helper/) before creating any new reusable UI component (buttons, progress bars, shadows, headers, etc.).
2. **Inspect Existing ViewModels**: Understand the data models and available properties before inventing new ones.
3. **Check Dependencies**: Look at existing Swift packages (`JellyfinAPI`, `SDWebImageSwiftUI`, etc.) before writing custom utilities.

---

## 5. Verification & Validation
- **Diagnostics**: Run `XcodeRefreshCodeIssuesInFile` on any file you edit to verify there are no compiler warnings or errors.
- **Build**: Ensure the project compiles cleanly without introducing breaking build issues.
