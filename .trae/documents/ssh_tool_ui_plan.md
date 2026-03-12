# Refactor UI with shadcn-vue

This plan outlines the steps to refactor the `ssh-tool-ui` project using `shadcn-vue`, replacing the existing hand-rolled UI components with a comprehensive component library and a consistent Blue theme.

## 1. Setup & Configuration

* **Install Dependencies**:

  * `shadcn-vue-next` (or `shadcn-vue` depending on latest), `clsx`, `tailwind-merge`, `class-variance-authority`, `radix-vue`, `lucide-vue-next`.

  * Ensure `tailwindcss` and `autoprefixer` are correctly configured.

* **Configure Path Aliases**:

  * Verify `tsconfig.app.json` and `vite.config.ts` correctly map `@` to `./src`.

* **Initialize shadcn-vue**:

  * Run `npx shadcn-vue@latest init`.

  * **Settings**:

    * Framework: `Vite`

    * Style: `New York` (Default)

    * Base Color: `Slate`

    * CSS Variables: `Yes`

    * Main CSS file: `src/assets/index.css` (or `src/style.css`)

    * Components directory: `src/components/ui`

    * Utils directory: `src/lib/utils.ts`

  * **Theme Customization**:

    * Update the CSS variables in the main CSS file to implement the **Blue** theme (using standard shadcn blue tokens).

## 2. Core Component Installation

Install the following components via CLI:

* `button` (Buttons)

* `dialog` (Modals)

* `input` (Text inputs)

* `label` (Form labels)

* `toast` (Notifications)

* `card` (Containers)

* `context-menu` (Right-click menus)

* `dropdown-menu` (Menu bars/actions)

* `tooltip` (Dock/Help tips)

* `skeleton` (Loading states)

* `table` (File list view)

* `sheet` (Side panels if needed)

* `popover` (General popups)

* `separator` (Dividers)

## 3. Component Migration Strategy

### 3.1 UI Primitives (`src/components/ui`)

* **`Modal.vue`**: Refactor to wrap `Dialog`, `DialogContent`, `DialogHeader`, `DialogFooter` from shadcn.

* **`Toast.vue`**: Replace with `Toaster` component and `useToast` composable.

* **`Loading.vue`**: Replace with `Skeleton` or a custom spinner using `lucide-vue-next`.

### 3.2 File System Components (`src/components/file`)

* **`FileGrid.vue`**: Use `Card` for file items.

* **`FileList.vue`**: Use `Table` for list view.

* **`FileContextMenu.vue`**: Use `ContextMenu` primitive.

* **`FileToolbar.vue`**: Use `Button` (variant: outline/ghost) and `Input` for search.

### 3.3 OS Components (`src/components/os`)

* **`Window.vue`**: Refactor using `Card` styling (border, shadow, bg) for the window frame.

* **`Dock.vue`**: Use `Tooltip` for icon labels.

* **`TopBar.vue`**: Use `DropdownMenu` for system menus.

* **`LoginScreen.vue`**: Use `Card`, `Input`, `Button` for the login form.

### 3.4 Views (`src/views`)

* **`Dashboard.vue`**: Layout using `Card`s for widgets.

* **`Files.vue`**: Integrate updated `File*` components.

* **`Terminal.vue`**: Ensure terminal container matches the theme (dark mode support).

## 4. Execution Steps

1. **Initialization**:

   * Install dependencies.

   * Run init command.

   * Apply Blue theme CSS variables.
2. **Install Components**:

   * Batch install all required components.
3. **Refactor Global UI**:

   * Update `App.vue` to include `Toaster`.

   * Replace `Modal.vue` logic.
4. **Refactor Features**:

   * Update File Browser (Grid/List/Context Menu).

   * Update OS Shell (Dock, Window, TopBar).
5. **Cleanup**:

   * Remove unused CSS classes.

   * verify all interactions.

## 5. Verification

* Check if all components render correctly.

* Verify "Blue" theme application.

* Test interactions (Modals opening, Toasts appearing, Context Menus working).

* Ensure responsiveness is maintained.

