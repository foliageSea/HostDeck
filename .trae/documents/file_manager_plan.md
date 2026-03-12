# Plan: File Manager Enhancements

## Goal
Implement three key features for the SSH Tool's file manager:
1.  **Independent File Management Instance**: Ensure the file manager runs on its own SSH session (specifically an SFTP session) so it doesn't block or interfere with terminal sessions.
2.  **Batch File Upload**: Improve the upload functionality to handle multiple files more robustly and provide better feedback.
3.  **Disable Right-Click on Empty Space**: Prevent the browser's context menu from appearing when right-clicking on empty areas of the file manager.

## Current State Analysis
-   **Session Management**: Currently, `Files.vue` and `file.ts` use `sshStore.sessionId`, which is shared with the active terminal. This means file operations compete with terminal output and if the terminal session closes, file access might be lost.
-   **Upload**: The frontend sends all selected files in a single multipart request. The backend iterates over parts. While functional, it lacks granular progress and error handling for individual files.
-   **Context Menu**: `FileList` and `FileGrid` emit `contextmenu` events only on file items. Clicks on empty space bubble up to the browser, showing the default context menu.

## Proposed Changes

### 1. Independent File Management Instance

**Backend (`dart`)**
-   **Refactor `SshSession` (`lib/server/models/ssh_session.dart`)**:
    -   Make `shell` property nullable (`SSHSession?`).
    -   Update `close()` to only close `shell` if it exists.
-   **Update `SshService` (`lib/server/services/ssh_service.dart`)**:
    -   Add `createSftpSession(String connectionId)` method.
    -   This method creates a `SshSession` with a valid `client` (reused via `connectionId`) but `shell` set to `null`.
    -   It returns a new unique `sessionId`.
-   **Update `FileController` (`lib/server/controllers/file_controller.dart`)**:
    -   Add `POST /api/files/session` endpoint.
    -   Accepts `connectionId`.
    -   Calls `_sshService.createSftpSession`.
    -   Returns the new `sessionId`.

**Frontend (`vue`)**
-   **Update `FileStore` (`ssh-tool-ui/src/stores/file.ts`)**:
    -   Add `sessionId` state (separate from `sshStore.sessionId`).
    -   Add `initSession()` action that calls `/api/files/session` using `sshStore.connectionId`.
    -   Update `fetchFiles` and other actions to use `this.sessionId`.
-   **Update `Files.vue` (`ssh-tool-ui/src/views/Files.vue`)**:
    -   Call `fileStore.initSession()` in `onMounted`.
    -   Update direct API calls (upload/download) to use `fileStore.sessionId`.

### 2. Batch File Upload

**Frontend (`vue`)**
-   **Update `Files.vue`**:
    -   Refactor `uploadFiles` to iterate over the `FileList`.
    -   Upload files sequentially (or with limited concurrency) using separate requests.
    -   Update `toast` to show progress (e.g., "Uploading 1/N...").
    -   This ensures that if one file fails, others can still proceed, and provides better feedback.

### 3. Disable Right-Click on Empty Space

**Frontend (`vue`)**
-   **Update `Files.vue`**:
    -   Add `@contextmenu.prevent` to the main container div (the one wrapping `FileList`/`FileGrid`).
    -   This will catch and suppress any context menu events that bubble up from empty space, while `FileList`/`FileGrid` will still handle valid file clicks (and should stop propagation).

## Verification Plan
1.  **Independent Instance**:
    -   Open a terminal and run a blocking command (e.g., `top`).
    -   Open the file manager and verify it lists files.
    -   Close the terminal tab. Verify file manager still works.
2.  **Batch Upload**:
    -   Select multiple files (3-5 files).
    -   Upload them.
    -   Verify all files appear in the list.
    -   Verify progress messages.
3.  **Right-Click**:
    -   Right-click on a file -> Custom menu should appear.
    -   Right-click on empty white space -> Nothing should happen (no browser menu).
