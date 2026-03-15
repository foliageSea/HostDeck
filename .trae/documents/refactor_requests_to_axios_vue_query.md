# Refactor Frontend Requests with Axios and Vue Query

## Goal
Replace all `fetch` API calls in the frontend (`ssh-tool-ui`) with `axios` for the HTTP client and `@tanstack/vue-query` for state/server state management.

## Steps

### 1. Preparation
- [ ] Install dependencies: `axios`, `@tanstack/vue-query`.
- [ ] Create `src/lib/http.ts` to configure a global `axios` instance with:
    - Base URL (if needed, or just relative).
    - Interceptor to handle 404 "Session not found" errors (replicating logic from `src/lib/fetch-interceptor.ts`).
- [ ] Register `VueQueryPlugin` in `src/main.ts`.

### 2. API Layer Setup
Create `src/api` directory and define API modules:
- [ ] `src/api/auth.ts`:
    - `connect(data)`: POST `/api/connect`
- [ ] `src/api/system.ts`:
    - `getMonitorStatus(sessionId)`: GET `/api/monitor`
- [ ] `src/api/terminal.ts`:
    - `createSession(connectionId, cols, rows)`: POST `/api/terminal/session`
    - `getSession(sessionId)`: GET `/api/terminal/session`
    - `resizeSession(sessionId, cols, rows)`: POST `/api/terminal/resize` (if exists, checking code)
- [ ] `src/api/files.ts`:
    - `createSession(connectionId)`: POST `/api/files/session`
    - `listFiles(sessionId, path)`: GET `/api/files/list`
    - `readFile(sessionId, path)`: GET `/api/files/read`
    - `uploadFile(sessionId, path, formData)`: POST `/api/files/upload`
    - `batchDownload(sessionId)`: GET `/api/files/batch-download`
    - `copy(sessionId, source, dest)`: POST `/api/files/copy`
    - `rename(sessionId, oldPath, newPath)`: POST `/api/files/rename`
    - `mkdir(sessionId, path)`: POST `/api/files/mkdir`
    - `deleteFile(sessionId, path)`: DELETE `/api/files/delete`

### 3. Refactoring Views and Components
- [ ] **Home.vue / LoginScreen.vue**:
    - Use `useMutation` for the connection request.
    - Replace direct `fetch` with `api.auth.connect`.
- [ ] **SystemMonitor.vue / Dashboard.vue**:
    - Use `useQuery` for polling system status.
    - Configure `refetchInterval` for auto-refresh.
    - Replace `fetch` with `api.system.getMonitorStatus`.
- [ ] **Terminal.vue**:
    - Use `useQuery` or `axios` directly for session checks/creation.
- [ ] **TextEditor.vue**:
    - Use `useQuery` for fetching file content (`readFile`).
    - Use `useMutation` for saving file (if applicable).
- [ ] **FileStore / Files.vue**:
    - Refactor `FileStore` to use `axios` for all mutation-like operations (copy, move, delete, rename, mkdir).
    - Refactor `fetchFiles` logic:
        - Option A: Keep `fetchFiles` in store but use `axios`.
        - Option B: Move list fetching to `useQuery` in `Files.vue` and update store state.
        - **Decision**: Use `axios` in `FileStore` for all operations first to ensure stability. For `fetchFiles`, we can still use `axios` inside the store action, or use `useQuery` in `Files.vue` and sync to store. given `FileStore` complexity, we will replace `fetch` with `axios` in `FileStore` actions.
        - *Correction*: The prompt asks to use `vue-query`. We will implement `useQuery` for `listFiles` in `Files.vue` or a composable, and let `FileStore` manage the *selected* files and operations. The `files` list can be derived from the query.

### 4. Cleanup
- [ ] Remove `src/lib/fetch-interceptor.ts` (logic moved to axios interceptor).
- [ ] Remove `setupFetchInterceptor` call in `main.ts`.
- [ ] Verify all `fetch` calls are gone.

## Verification
- [ ] Check if `Session not found` still triggers a redirect/toast (via axios interceptor).
- [ ] Verify System Monitor updates in real-time.
- [ ] Verify File Manager lists files, handles navigation, and performs operations (upload, delete, etc.).
- [ ] Verify Terminal connects and runs.
