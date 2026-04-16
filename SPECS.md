# Espalier — EARS Requirements Specification

Requirements for a macOS worktree-aware terminal multiplexer built on libghostty.

## 1. App Layout

### 1.1 Window Structure

**REQ-1.1.1** The application shall display a single main window with a resizable sidebar on the left and a terminal content area on the right.

**REQ-1.1.2** The sidebar shall be resizable via a drag handle between the sidebar and the terminal content area.

**REQ-1.1.3** The terminal content area shall display a breadcrumb bar showing the selected repository name, worktree branch, and filesystem path above the terminal split layout.

### 1.2 Sidebar — Repository List

**REQ-1.2.1** The sidebar shall display an ordered list of repositories, each expandable to show its worktrees.

**REQ-1.2.2** Each repository entry shall be collapsible and expandable by clicking its disclosure indicator.

**REQ-1.2.3** When a repository is expanded, the sidebar shall display the repository's own working directory as the first child entry, labeled by its current branch name.

**REQ-1.2.4** When a repository is expanded, the sidebar shall display each linked worktree as a child entry beneath the repository's own working directory, labeled by branch name.

**REQ-1.2.5** The sidebar shall display an "Add Repository" button at the bottom.

**REQ-1.2.6** When the user clicks a worktree or repository working directory entry, the terminal content area shall switch to display that entry's terminal layout.

**REQ-1.2.7** When the user right-clicks a sidebar entry, the application shall display a context menu with actions appropriate to the entry's current state.

### 1.3 Adding Repositories

**REQ-1.3.1** When the user clicks "Add Repository", the application shall present a standard macOS open panel for selecting a directory.

**REQ-1.3.2** When the user drops a directory onto the sidebar, the application shall add it as a repository.

**REQ-1.3.3** When the user adds a directory that is a git worktree (rather than a repository root), the application shall trace back to the parent repository, add the full repository with all its worktrees, and auto-select the added worktree.

**REQ-1.3.4** If the user adds a directory that is not a git repository or worktree, then the application shall display an error message and not add the directory.

**REQ-1.3.5** If the user adds a repository that is already in the sidebar, then the application shall not create a duplicate and shall select the existing entry.

## 2. Worktree Entry States

### 2.1 State Definitions

**REQ-2.1.1** Each worktree entry shall have one of three states: closed, running, or stale.

**REQ-2.1.2** While a worktree entry is in the closed state, the sidebar shall display a hollow dot indicator (○) next to it.

**REQ-2.1.3** While a worktree entry is in the running state, the sidebar shall display a green dot indicator (●) next to it.

**REQ-2.1.4** While a worktree entry is in the stale state, the sidebar shall display a warning icon (⚠), strikethrough text, and grayed-out appearance.

### 2.2 Attention Overlay

**REQ-2.2.1** A worktree entry in any state may additionally have an attention overlay.

**REQ-2.2.2** While a worktree entry has an attention overlay, the sidebar shall display a red badge showing the attention text.

**REQ-2.2.3** When the user clicks a worktree entry that has an attention overlay, the application shall clear the attention overlay.

**REQ-2.2.4** When the CLI sends a clear message for a worktree, the application shall clear the attention overlay.

**REQ-2.2.5** When an attention overlay was set with an auto-clear duration, the application shall clear the attention overlay after that duration elapses.

## 3. Terminal Lifecycle

### 3.1 Starting Terminals

**REQ-3.1.1** When the user clicks a worktree entry in the closed state that has no saved split tree, the application shall create a single terminal pane with its working directory set to the worktree path and transition the entry to the running state.

**REQ-3.1.2** When the user clicks a worktree entry in the closed state that has a saved split tree, the application shall recreate terminal panes matching the saved split tree topology, each with its working directory set to the worktree path, and transition the entry to the running state.

### 3.2 Switching Between Worktrees

**REQ-3.2.1** When the user switches from one running worktree to another, the application shall hide the previous worktree's terminal views without destroying the terminal surfaces or their running processes.

**REQ-3.2.2** When the user switches back to a previously running worktree, the application shall restore the terminal views with all processes still running.

**REQ-3.2.3** When the user switches back to a running worktree, the application shall restore keyboard focus to the pane that was focused when the user last switched away.

### 3.3 Splitting

**REQ-3.3.1** When the user triggers a horizontal split, the application shall insert a new terminal pane to the right of the focused pane with a 50/50 ratio.

**REQ-3.3.2** When the user triggers a vertical split, the application shall insert a new terminal pane below the focused pane with a 50/50 ratio.

**REQ-3.3.3** The new terminal pane created by a split shall have its working directory set to the worktree root path.

### 3.4 Resizing Splits

**REQ-3.4.1** The application shall display a draggable divider between split panes.

**REQ-3.4.2** When the user drags a divider, the application shall resize the adjacent panes proportionally.

### 3.5 Closing a Pane

**REQ-3.5.1** When the user closes a terminal pane, the application shall remove it from the split tree and allow the sibling pane to fill the vacated space.

**REQ-3.5.2** When the user closes the last terminal pane in a worktree, the application shall transition the worktree entry to the closed state.

### 3.6 Stopping a Worktree

**REQ-3.6.1** When the user triggers "Stop" on a running worktree, if any terminal surface has a running process, then the application shall display a confirmation dialog before proceeding.

**REQ-3.6.2** When the user confirms stopping a worktree, the application shall close and free all terminal surfaces in the worktree's split tree, preserve the split tree topology, and transition the entry to the closed state.

### 3.7 Focus Management

**REQ-3.7.1** When the user clicks a terminal pane, the application shall set keyboard focus to that pane.

**REQ-3.7.2** The application shall support keyboard navigation between panes using directional shortcuts (e.g., Cmd+Opt+Arrow).

**REQ-3.7.3** When the user navigates between panes via keyboard, the application shall use the split tree's spatial layout to determine the target pane.

## 4. Worktree Discovery & Monitoring

### 4.1 Initial Discovery

**REQ-4.1.1** When a repository is added, the application shall run `git worktree list --porcelain` and populate the sidebar with all discovered worktrees in the closed state.

### 4.2 Filesystem Monitoring

**REQ-4.2.1** While a repository is in the sidebar, the application shall watch the repository's `.git/worktrees/` directory for changes using FSEvents.

**REQ-4.2.2** When a change is detected in `.git/worktrees/`, the application shall re-run `git worktree list --porcelain` and reconcile the results against the current model.

**REQ-4.2.3** While a repository is in the sidebar, the application shall watch each worktree's directory path for deletion using FSEvents.

**REQ-4.2.4** While a repository is in the sidebar, the application shall watch each worktree's HEAD reference for changes using FSEvents to detect branch switches.

### 4.3 Change Handling

**REQ-4.3.1** When a new worktree is detected, the application shall add a new entry in the closed state and briefly flash its background highlight.

**REQ-4.3.2** When a worktree is removed via `git worktree remove`, the application shall transition the entry to the stale state.

**REQ-4.3.3** When a worktree's directory is deleted externally, the application shall transition the entry to the stale state.

**REQ-4.3.4** While a worktree entry is in the stale state and was running, the application shall keep terminal surfaces alive until the user explicitly stops the entry.

**REQ-4.3.5** When a worktree's HEAD reference changes, the application shall update the entry's branch label in the sidebar.

**REQ-4.3.6** While a worktree entry is in the stale state, the context menu shall include a "Dismiss" action that removes the entry from the sidebar.

## 5. Attention Notification System

### 5.1 CLI Tool

**REQ-5.1.1** The application shall include a CLI binary (`espalier`) in the app bundle at `Espalier.app/Contents/MacOS/espalier`.

**REQ-5.1.2** The CLI shall support the command `espalier notify "<text>"` to set attention on the worktree containing the current working directory.

**REQ-5.1.3** The CLI shall support the flag `--clear-after <seconds>` to auto-clear the attention after a specified duration.

**REQ-5.1.4** The CLI shall support the command `espalier notify --clear` to clear attention on the current worktree.

**REQ-5.1.5** The CLI shall resolve the current worktree by walking up from `$PWD` looking for a `.git` file (linked worktree) or `.git` directory (main working tree).

### 5.2 Communication Protocol

**REQ-5.2.1** The application shall listen on a Unix domain socket at `~/Library/Application Support/Espalier/espalier.sock`.

**REQ-5.2.2** The CLI shall communicate with the application by sending JSON messages over the Unix domain socket.

**REQ-5.2.3** The application shall support the following message types over the socket:
- Notify: `{"type": "notify", "path": "<worktree-path>", "text": "<text>"}`
- Notify with auto-clear: `{"type": "notify", "path": "<worktree-path>", "text": "<text>", "clearAfter": <seconds>}`
- Clear: `{"type": "clear", "path": "<worktree-path>"}`

**REQ-5.2.4** The application shall set the environment variable `ESPALIER_SOCK` in each terminal surface's environment, pointing to the socket path.

**REQ-5.2.5** The CLI shall read the `ESPALIER_SOCK` environment variable to locate the socket.

### 5.3 Error Handling

**REQ-5.3.1** If the application is not running, then the CLI shall print "Espalier is not running" and exit with code 1.

**REQ-5.3.2** If the current working directory is not inside a tracked worktree, then the CLI shall print "Not inside a tracked worktree" and exit with code 1.

**REQ-5.3.3** If the socket is unresponsive, then the CLI shall time out after 2 seconds, print an error, and exit with code 1.

### 5.4 CLI Distribution

**REQ-5.4.1** On first launch, the application shall offer to create a symlink at `/usr/local/bin/espalier` pointing to the CLI binary in the app bundle.

**REQ-5.4.2** The application shall provide a menu item (Espalier -> Install CLI Tool...) to create or update the symlink.

## 6. Persistence

### 6.1 Storage

**REQ-6.1.1** The application shall store all persistent state in `~/Library/Application Support/Espalier/`.

**REQ-6.1.2** The application shall persist state to a `state.json` file containing: the ordered list of repositories and their worktrees, per-worktree split tree topology and `wasRunning` flag, selected worktree, window frame, and sidebar width.

### 6.2 Save Triggers

**REQ-6.2.1** The application shall save state when any of the following occur: split tree changes, worktree state changes, repository added or removed, selection changes, window resize or move (debounced), app moving to background, or app quit.

### 6.3 Restore on Launch

**REQ-6.3.1** When the application launches with an existing `state.json`, it shall restore the sidebar with all saved repositories and worktrees.

**REQ-6.3.2** When the application launches, it shall restore the saved split tree topology for each worktree.

**REQ-6.3.3** When the application launches, it shall automatically start fresh terminal surfaces for each worktree that had `wasRunning: true`.

**REQ-6.3.4** When the application launches, it shall restore the window frame position, size, and sidebar width.

**REQ-6.3.5** When the application launches, it shall re-select the previously selected worktree.

**REQ-6.3.6** When the application launches, it shall run worktree discovery for each repository to reconcile saved state against current disk state.

### 6.4 Non-Persisted State

**REQ-6.4.1** The application shall not persist shell scrollback, terminal screen buffer content, or the specific processes that were running.

## 7. Technology Constraints

**REQ-7.1** The application shall be built in Swift using SwiftUI for app chrome and AppKit for terminal view hosting.

**REQ-7.2** The application shall use libghostty (via the libghostty-spm Swift Package) as its terminal engine.

**REQ-7.3** The application shall target macOS 14 Sonoma as its minimum supported version.

**REQ-7.4** The application shall reuse the following components from the Ghostty project (MIT-licensed): `SplitTree`, `SplitView`, `Ghostty.Surface`, `Ghostty.App`, `Ghostty.Config`, and `SurfaceView_AppKit`.
