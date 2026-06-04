#ifndef DEVNOTE_QT_BRIDGE_H
#define DEVNOTE_QT_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) || defined(_WIN64)
  #define DEVNOTE_QT_EXPORT __declspec(dllexport)
#else
  #define DEVNOTE_QT_EXPORT __attribute__((visibility("default")))
#endif

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/** Initialize the Qt application. Must be called once before any other
 *  function. Returns 0 on success, -1 on error. */
DEVNOTE_QT_EXPORT int devnote_qt_init(int argc, char* argv[]);

/** Destroy the Qt application and free all resources. */
DEVNOTE_QT_EXPORT void devnote_qt_destroy(void);

// ---------------------------------------------------------------------------
// Canvas management
// ---------------------------------------------------------------------------

/** Create a QGraphicsView canvas attached to the given native parent window
 *  handle (HWND on Windows, NSView* on macOS, X11 Window on Linux).
 *  Returns an opaque handle (pointer) or NULL on failure. */
DEVNOTE_QT_EXPORT void* devnote_qt_create_canvas(void* parent_window_handle);

/** Destroy a previously created canvas. */
DEVNOTE_QT_EXPORT void devnote_qt_destroy_canvas(void* canvas_handle);

// ---------------------------------------------------------------------------
// Node operations
// ---------------------------------------------------------------------------

/** Add a node to the canvas. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_add_node(
    void* canvas_handle,
    const char* node_id,
    const char* content,
    double x,
    double y,
    double w,
    double h);

/** Update a node's position and size. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_update_node(
    void* canvas_handle,
    const char* node_id,
    double x,
    double y,
    double w,
    double h);

/** Remove a node (and its incident edges) from the canvas. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_remove_node(
    void* canvas_handle,
    const char* node_id);

// ---------------------------------------------------------------------------
// Edge operations
// ---------------------------------------------------------------------------

/** Add a directed edge between two nodes. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_add_edge(
    void* canvas_handle,
    const char* edge_id,
    const char* source_id,
    const char* target_id,
    const char* label);

/** Remove an edge from the canvas. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_remove_edge(
    void* canvas_handle,
    const char* edge_id);

// ---------------------------------------------------------------------------
// Canvas-level operations
// ---------------------------------------------------------------------------

/** Remove all nodes and edges from the canvas. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_clear(void* canvas_handle);

/** Register a callback for canvas events. Pass NULL to unregister.
 *  The callback receives an event_type string (e.g. "node_moved",
 *  "node_clicked", "node_double_clicked", "edge_created", "canvas_clicked")
 *  and a JSON payload. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_set_callback(
    void* canvas_handle,
    void (*callback)(const char* event_type, const char* json_data));

/** Set the zoom level of the canvas (1.0 = 100%). */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_set_zoom(
    void* canvas_handle,
    double zoom);

/** Fit all nodes into the current viewport. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_fit_all(void* canvas_handle);

/** Export the current canvas view as a PNG image to the given file path. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_export_image(
    void* canvas_handle,
    const char* path);

// ---------------------------------------------------------------------------
// JSON serialization (Obsidian Canvas format)
// ---------------------------------------------------------------------------

/** Load canvas data from a JSON string in Obsidian Canvas format. */
DEVNOTE_QT_EXPORT void devnote_qt_canvas_load_json(
    void* canvas_handle,
    const char* json);

/** Save the current canvas state to a JSON string in Obsidian Canvas format.
 *  The caller must free the returned string using devnote_qt_free_string(). */
DEVNOTE_QT_EXPORT char* devnote_qt_canvas_save_json(void* canvas_handle);

/** Free a string previously returned by the library. */
DEVNOTE_QT_EXPORT void devnote_qt_free_string(char* s);

#ifdef __cplusplus
}
#endif

#endif // DEVNOTE_QT_BRIDGE_H