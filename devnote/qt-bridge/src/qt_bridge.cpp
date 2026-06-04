#include "devnote_qt_bridge.h"

#include <QtWidgets/QApplication>
#include <QtWidgets/QGraphicsScene>
#include <QtWidgets/QGraphicsView>
#include <QtWidgets/QGraphicsRectItem>
#include <QtWidgets/QGraphicsTextItem>
#include <QtWidgets/QGraphicsLineItem>
#include <QtWidgets/QGraphicsPolygonItem>
#include <QPainter>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QString>
#include <QPen>
#include <QBrush>
#include <QFont>
#include <QColor>
#include <QPointF>
#include <QLineF>
#include <QPolygonF>
#include <QMutex>
#include <QMutexLocker>
#include <QMap>
#include <QWheelEvent>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <algorithm>

// ============================================================================
// Internal types
// ============================================================================

// Callback type stored internally
using CanvasCallback = void (*)(const char* event_type, const char* json_data);

// ---------------------------------------------------------------------------
// Graphics items
// ---------------------------------------------------------------------------

static const double HANDLE_SIZE = 8.0;
static const double ARROW_SIZE   = 10.0;
static const double MIN_NODE_W   = 80.0;
static const double MIN_NODE_H   = 60.0;

/**
 * Resizable, movable node displayed as a rounded rectangle with text.
 */
class CanvasNodeItem : public QGraphicsRectItem {
public:
    CanvasNodeItem(const QString& id, const QString& content,
                   double x, double y, double w, double h)
        : QGraphicsRectItem(0, 0, w, h)
        , node_id_(id)
        , resizing_(false)
        , resize_handle_(-1)
    {
        setPos(x, y);

        setFlag(QGraphicsItem::ItemIsMovable, true);
        setFlag(QGraphicsItem::ItemIsSelectable, true);
        setFlag(QGraphicsItem::ItemSendsGeometryChanges, true);
        setAcceptHoverEvents(true);

        setPen(QPen(QColor(100, 100, 100), 2));
        setBrush(QBrush(QColor(240, 240, 245)));

        text_item_ = new QGraphicsTextItem(content, this);
        text_item_->setDefaultTextColor(QColor(30, 30, 30));
        text_item_->setFont(QFont("sans-serif", 11));
        text_item_->setPos(6, 6);
        text_item_->setTextWidth(w - 12);
        text_item_->setFlag(QGraphicsItem::ItemIsSelectable, false);
        text_item_->setFlag(QGraphicsItem::ItemIsMovable, false);
    }

    QString nodeId() const { return node_id_; }
    QString content() const { return text_item_->toPlainText(); }
    void setContent(const QString& text) { text_item_->setPlainText(text); }

    // Override paint to draw rounded rect + resize handles
    void paint(QPainter* painter, const QStyleOptionGraphicsItem*, QWidget*) override {
        QRectF r = rect();
        painter->setPen(pen());
        painter->setBrush(brush());
        painter->drawRoundedRect(r, 6, 6);

        // Resize handles (8 corners + midpoints)
        if (isSelected()) {
            painter->setBrush(QBrush(QColor(66, 133, 244)));
            painter->setPen(Qt::NoPen);
            const double hw = HANDLE_SIZE / 2.0;
            QPointF pts[8] = {
                r.topLeft(),     QPointF(r.center().x(), r.top()),
                r.topRight(),    QPointF(r.right(), r.center().y()),
                r.bottomRight(), QPointF(r.center().x(), r.bottom()),
                r.bottomLeft(),  QPointF(r.left(), r.center().y())
            };
            for (int i = 0; i < 8; ++i) {
                painter->drawRect(QRectF(pts[i].x() - hw, pts[i].y() - hw,
                                          HANDLE_SIZE, HANDLE_SIZE));
            }
        }
    }

    QVariant itemChange(GraphicsItemChange change, const QVariant& value) override {
        if (change == ItemPositionHasChanged) {
            // Child text item position is in local coords and does not need updating.
            // Update connected edges.
        }
        return QGraphicsRectItem::itemChange(change, value);
    }

    // Resize handle detection
    void mousePressEvent(QGraphicsSceneMouseEvent* event) override {
        resize_handle_ = hitHandle(event->pos());
        if (resize_handle_ >= 0) {
            resizing_ = true;
            resize_start_pos_ = event->scenePos();
            resize_start_rect_ = rect();
            setFlag(ItemIsMovable, false);
        } else {
            QGraphicsRectItem::mousePressEvent(event);
        }
    }

    void mouseMoveEvent(QGraphicsSceneMouseEvent* event) override {
        if (resizing_) {
            QPointF delta = event->scenePos() - resize_start_pos_;
            QRectF newRect = resize_start_rect_;
            switch (resize_handle_) {
                case 0: { // Top-Left
                    newRect.setTopLeft(newRect.topLeft() + delta);
                    break;
                }
                case 1: { // Top-Center
                    newRect.setTop(newRect.top() + delta.y());
                    break;
                }
                case 2: { // Top-Right
                    newRect.setTopRight(newRect.topRight() + delta);
                    break;
                }
                case 3: { // Right-Center
                    newRect.setRight(newRect.right() + delta.x());
                    break;
                }
                case 4: { // Bottom-Right
                    newRect.setBottomRight(newRect.bottomRight() + delta);
                    break;
                }
                case 5: { // Bottom-Center
                    newRect.setBottom(newRect.bottom() + delta.y());
                    break;
                }
                case 6: { // Bottom-Left
                    newRect.setBottomLeft(newRect.bottomLeft() + delta);
                    break;
                }
                case 7: { // Left-Center
                    newRect.setLeft(newRect.left() + delta.x());
                    break;
                }
                default: break;
            }
            if (newRect.width() < MIN_NODE_W) {
                if (resize_handle_ == 0 || resize_handle_ == 6 || resize_handle_ == 7)
                    newRect.setLeft(newRect.right() - MIN_NODE_W);
                else
                    newRect.setRight(newRect.left() + MIN_NODE_W);
            }
            if (newRect.height() < MIN_NODE_H) {
                if (resize_handle_ == 0 || resize_handle_ == 1 || resize_handle_ == 2)
                    newRect.setTop(newRect.bottom() - MIN_NODE_H);
                else
                    newRect.setBottom(newRect.top() + MIN_NODE_H);
            }
            prepareGeometryChange();
            setRect(newRect);
            text_item_->setTextWidth(newRect.width() - 12);
        } else {
            QGraphicsRectItem::mouseMoveEvent(event);
        }
    }

    void mouseReleaseEvent(QGraphicsSceneMouseEvent* event) override {
        if (resizing_) {
            resizing_ = false;
            resize_handle_ = -1;
            setFlag(ItemIsMovable, true);
        } else {
            QGraphicsRectItem::mouseReleaseEvent(event);
        }
    }

private:
    int hitHandle(const QPointF& pos) const {
        QRectF r = rect();
        const double hw = HANDLE_SIZE / 2.0;
        QPointF pts[8] = {
            r.topLeft(),     QPointF(r.center().x(), r.top()),
            r.topRight(),    QPointF(r.right(), r.center().y()),
            r.bottomRight(), QPointF(r.center().x(), r.bottom()),
            r.bottomLeft(),  QPointF(r.left(), r.center().y())
        };
        for (int i = 0; i < 8; ++i) {
            QRectF hRect(pts[i].x() - hw, pts[i].y() - hw, HANDLE_SIZE, HANDLE_SIZE);
            if (hRect.contains(pos)) return i;
        }
        return -1;
    }

    QString node_id_;
    QGraphicsTextItem* text_item_;
    bool resizing_;
    int resize_handle_;
    QPointF resize_start_pos_;
    QRectF resize_start_rect_;
};

// ---------------------------------------------------------------------------

/**
 * Directed edge between two nodes with an arrow head.
 */
class CanvasEdgeItem : public QGraphicsLineItem {
public:
    CanvasEdgeItem(const QString& id, CanvasNodeItem* src, CanvasNodeItem* dst,
                   const QString& label)
        : QGraphicsLineItem()
        , edge_id_(id)
        , source_(src)
        , target_(dst)
        , label_text_(nullptr)
    {
        setPen(QPen(QColor(120, 120, 130), 2));
        setZValue(-1);
        if (!label.isEmpty()) {
            label_text_ = new QGraphicsTextItem(label, this);
            label_text_->setDefaultTextColor(QColor(80, 80, 80));
            label_text_->setFont(QFont("sans-serif", 9));
            label_text_->setFlag(QGraphicsItem::ItemIsSelectable, false);
            label_text_->setFlag(QGraphicsItem::ItemIsMovable, false);
        }
        updatePosition();
    }

    QString edgeId() const { return edge_id_; }

    void updatePosition() {
        QRectF sr = source_->sceneBoundingRect();
        QRectF tr = target_->sceneBoundingRect();

        QPointF sc = sr.center();
        QPointF tc = tr.center();

        QLineF line(sc, tc);

        // Clip to node borders
        QPointF p1, p2;
        QLineF topLine(sr.topLeft(), sr.topRight());
        QLineF botLine(sr.bottomLeft(), sr.bottomRight());
        QLineF leftLine(sr.topLeft(), sr.bottomLeft());
        QLineF rightLine(sr.topRight(), sr.bottomRight());

        QPointF isect;
        // Source side
        if (line.intersects(topLine, &isect) == QLineF::BoundedIntersection) p1 = isect;
        else if (line.intersects(botLine, &isect) == QLineF::BoundedIntersection) p1 = isect;
        else if (line.intersects(leftLine, &isect) == QLineF::BoundedIntersection) p1 = isect;
        else if (line.intersects(rightLine, &isect) == QLineF::BoundedIntersection) p1 = isect;
        else p1 = sc;

        QLineF topLine2(tr.topLeft(), tr.topRight());
        QLineF botLine2(tr.bottomLeft(), tr.bottomRight());
        QLineF leftLine2(tr.topLeft(), tr.bottomLeft());
        QLineF rightLine2(tr.topRight(), tr.bottomRight());

        QLineF backLine(tc, sc);
        if (backLine.intersects(topLine2, &isect) == QLineF::BoundedIntersection) p2 = isect;
        else if (backLine.intersects(botLine2, &isect) == QLineF::BoundedIntersection) p2 = isect;
        else if (backLine.intersects(leftLine2, &isect) == QLineF::BoundedIntersection) p2 = isect;
        else if (backLine.intersects(rightLine2, &isect) == QLineF::BoundedIntersection) p2 = isect;
        else p2 = tc;

        setLine(QLineF(p1, p2));

        // Label position
        if (label_text_) {
            QPointF mid = (p1 + p2) / 2.0;
            label_text_->setPos(mid);
        }

        // Arrow head
        QLineF arrowLine(p2, p1);
        double angle = std::atan2(-arrowLine.dy(), arrowLine.dx());
        double arrowSize = ARROW_SIZE;
        QPointF arrowP1 = p2 + QPointF(std::cos(angle + M_PI / 6.0) * arrowSize,
                                        std::sin(angle + M_PI / 6.0) * arrowSize);
        QPointF arrowP2 = p2 + QPointF(std::cos(angle - M_PI / 6.0) * arrowSize,
                                        std::sin(angle - M_PI / 6.0) * arrowSize);
        arrow_head_ = QPolygonF({p2, arrowP1, arrowP2});
    }

    void paint(QPainter* painter, const QStyleOptionGraphicsItem*, QWidget*) override {
        painter->setPen(pen());
        painter->drawLine(line());
        // Draw arrowhead
        painter->setBrush(pen().color());
        painter->setPen(Qt::NoPen);
        painter->drawPolygon(arrow_head_);
    }

    CanvasNodeItem* sourceNode() const { return source_; }
    CanvasNodeItem* targetNode() const { return target_; }

private:
    QString edge_id_;
    CanvasNodeItem* source_;
    CanvasNodeItem* target_;
    QGraphicsTextItem* label_text_;
    QPolygonF arrow_head_;
};

// ============================================================================
// CanvasWidget: QGraphicsView owner
// ============================================================================

class CanvasWidget : public QGraphicsView {
    Q_OBJECT
public:
    explicit CanvasWidget(QWidget* parent = nullptr)
        : QGraphicsView(parent)
        , scene_(new QGraphicsScene(this))
        , callback_(nullptr)
        , grid_layout_spacing_(280.0)
    {
        setScene(scene_);
        setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing |
                        QPainter::SmoothPixmapTransform);
        setDragMode(QGraphicsView::RubberBandDrag);
        setViewportUpdateMode(QGraphicsView::SmartViewportUpdate);
        setTransformationAnchor(QGraphicsView::AnchorUnderMouse);
        setResizeAnchor(QGraphicsView::AnchorUnderMouse);
        setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOn);
        setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOn);
        scene_->setSceneRect(-5000, -5000, 10000, 10000);
    }

    ~CanvasWidget() override {
        clearCanvas();
    }

    // ---- Node operations ----

    void addNode(const QString& id, const QString& content, double x, double y, double w, double h) {
        auto* item = new CanvasNodeItem(id, content, x, y, w, h);
        scene_->addItem(item);
        nodes_[id] = item;
    }

    void updateNode(const QString& id, double x, double y, double w, double h) {
        auto it = nodes_.find(id);
        if (it == nodes_.end()) return;
        auto* item = it->second;
        item->setPos(x, y);
        QRectF oldR = item->rect();
        if (oldR.width() != w || oldR.height() != h) {
            item->setRect(0, 0, w, h);
        }
        // Update all connected edges
        updateEdgesForNode(item);
    }

    void removeNode(const QString& id) {
        auto it = nodes_.find(id);
        if (it == nodes_.end()) return;
        auto* item = it->second;

        // Remove incident edges
        auto edgeIt = edges_.begin();
        while (edgeIt != edges_.end()) {
            auto* edge = edgeIt->second;
            if (edge->sourceNode() == item || edge->targetNode() == item) {
                scene_->removeItem(edge);
                delete edge;
                edgeIt = edges_.erase(edgeIt);
            } else {
                ++edgeIt;
            }
        }

        scene_->removeItem(item);
        delete item;
        nodes_.erase(it);
    }

    // ---- Edge operations ----

    void addEdge(const QString& id, const QString& srcId, const QString& dstId, const QString& label) {
        auto sit = nodes_.find(srcId);
        auto dit = nodes_.find(dstId);
        if (sit == nodes_.end() || dit == nodes_.end()) return;
        auto* edge = new CanvasEdgeItem(id, sit->second, dit->second, label);
        scene_->addItem(edge);
        edges_[id] = edge;
    }

    void removeEdge(const QString& id) {
        auto it = edges_.find(id);
        if (it == edges_.end()) return;
        scene_->removeItem(it->second);
        delete it->second;
        edges_.erase(it);
    }

    // ---- Canvas-level ----

    void clearCanvas() {
        for (auto& p : edges_) { scene_->removeItem(p.second); delete p.second; }
        edges_.clear();
        for (auto& p : nodes_) { scene_->removeItem(p.second); delete p.second; }
        nodes_.clear();
    }

    void setZoom(double zoom) {
        resetTransform();
        scale(zoom, zoom);
    }

    void fitAll() {
        if (nodes_.empty()) return;
        QRectF bounding;
        for (auto& p : nodes_) {
            bounding = bounding.united(p.second->sceneBoundingRect());
        }
        fitInView(bounding.adjusted(-40, -40, 40, 40), Qt::KeepAspectRatio);
    }

    void exportImage(const QString& path) {
        QRectF full = scene_->itemsBoundingRect().adjusted(-20, -20, 20, 20);
        if (full.isEmpty()) full = QRectF(0, 0, 800, 600);
        QImage img(full.size().toSize() * 2, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::white);
        QPainter painter(&img);
        painter.setRenderHint(QPainter::Antialiasing);
        scene_->render(&painter, QRectF(), full);
        painter.end();
        img.save(path, "PNG");
    }

    // ---- Callback ----

    void setCallback(CanvasCallback cb) {
        QMutexLocker lock(&callback_mutex_);
        callback_ = cb;
    }

    // ---- JSON ----

    void loadJson(const QString& json) {
        clearCanvas();
        QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
        if (!doc.isObject()) return;
        QJsonObject root = doc.object();
        QJsonArray nodesArr = root.value("nodes").toArray();
        QJsonArray edgesArr = root.value("edges").toArray();

        for (const auto& v : nodesArr) {
            QJsonObject o = v.toObject();
            QString id = o.value("id").toString();
            QString type = o.value("type").toString("text");
            double x = o.value("x").toDouble(0);
            double y = o.value("y").toDouble(0);
            double w = o.value("width").toDouble(200);
            double h = o.value("height").toDouble(120);
            QString content;
            if (o.contains("file"))
                content = o.value("file").toString();
            else
                content = o.value("content").toString(type);
            if (o.contains("color")) {
                // Color will be applied when we rebuild
            }
            addNode(id, content, x, y, w, h);
            auto it = nodes_.find(id);
            if (it != nodes_.end() && o.contains("color")) {
                QColor c(o.value("color").toString());
                if (c.isValid()) {
                    it->second->setBrush(QBrush(c.lighter(160)));
                }
            }
        }

        for (const auto& v : edgesArr) {
            QJsonObject o = v.toObject();
            QString id = o.value("id").toString();
            QString from = o.value("fromNode").toString();
            QString to = o.value("toNode").toString();
            QString label = o.value("label").toString();
            addEdge(id, from, to, label);
            auto it = edges_.find(id);
            if (it != edges_.end() && o.contains("color")) {
                QColor c(o.value("color").toString());
                if (c.isValid()) {
                    it->second->setPen(QPen(c, 2));
                }
            }
        }
    }

    QString saveJson() const {
        QJsonObject root;
        QJsonArray nodesArr;
        for (const auto& p : nodes_) {
            auto* item = p.second;
            QJsonObject o;
            o["id"] = item->nodeId();
            o["type"] = "text";
            o["x"] = item->scenePos().x();
            o["y"] = item->scenePos().y();
            o["width"] = item->rect().width();
            o["height"] = item->rect().height();
            o["content"] = item->content();
            nodesArr.append(o);
        }
        root["nodes"] = nodesArr;

        QJsonArray edgesArr;
        for (const auto& p : edges_) {
            auto* item = p.second;
            QJsonObject o;
            o["id"] = item->edgeId();
            o["fromNode"] = item->sourceNode()->nodeId();
            o["toNode"] = item->targetNode()->nodeId();
            edgesArr.append(o);
        }
        root["edges"] = edgesArr;

        return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
    }

    // ---- Layout ----

    void applyGridLayout() {
        if (nodes_.empty()) return;
        int cols = static_cast<int>(std::ceil(std::sqrt(static_cast<double>(nodes_.size()))));
        int i = 0;
        for (auto& p : nodes_) {
            int row = i / cols;
            int col = i % cols;
            p.second->setPos(col * grid_layout_spacing_, row * grid_layout_spacing_);
            ++i;
        }
        updateAllEdges();
    }

    void applyForceLayout() {
        if (nodes_.empty()) return;
        const int n = static_cast<int>(nodes_.size());
        const int iterations = 200;
        const double k = 300.0;
        const double gravity = 0.01;
        const double damping = 0.9;

        std::vector<CanvasNodeItem*> items;
        items.reserve(n);
        std::vector<double> vx(n, 0.0), vy(n, 0.0);
        for (auto& p : nodes_) items.push_back(p.second);

        for (int iter = 0; iter < iterations; ++iter) {
            // Repulsion
            for (int a = 0; a < n; ++a) {
                for (int b = a + 1; b < n; ++b) {
                    double dx = items[b]->pos().x() - items[a]->pos().x();
                    double dy = items[b]->pos().y() - items[a]->pos().y();
                    double dist = std::max(1.0, std::sqrt(dx * dx + dy * dy));
                    double force = k * k / dist;
                    double fx = dx / dist * force;
                    double fy = dy / dist * force;
                    vx[a] -= fx; vy[a] -= fy;
                    vx[b] += fx; vy[b] += fy;
                }
            }
            // Attraction (edges)
            for (auto& ep : edges_) {
                auto* e = ep.second;
                int ai = -1, bi = -1;
                for (int i = 0; i < n; ++i) {
                    if (items[i] == e->sourceNode()) ai = i;
                    if (items[i] == e->targetNode()) bi = i;
                }
                if (ai < 0 || bi < 0) continue;
                double dx = items[bi]->pos().x() - items[ai]->pos().x();
                double dy = items[bi]->pos().y() - items[ai]->pos().y();
                double dist = std::max(1.0, std::sqrt(dx * dx + dy * dy));
                double force = (dist - k) * 0.05;
                double fx = dx / dist * force;
                double fy = dy / dist * force;
                vx[ai] += fx; vy[ai] += fy;
                vx[bi] -= fx; vy[bi] -= fy;
            }
            // Gravity + damping
            for (int i = 0; i < n; ++i) {
                vx[i] -= items[i]->pos().x() * gravity;
                vy[i] -= items[i]->pos().y() * gravity;
                vx[i] *= damping;
                vy[i] *= damping;
                items[i]->setPos(items[i]->pos().x() + vx[i],
                                 items[i]->pos().y() + vy[i]);
            }
        }
        updateAllEdges();
    }

    // ---- Mouse events ----

    void mousePressEvent(QMouseEvent* event) override {
        QGraphicsView::mousePressEvent(event);
        if (!event->isAccepted() && event->button() == Qt::LeftButton) {
            // Canvas background clicked
            emitEvent("canvas_clicked",
                       QString("{\"x\":%1,\"y\":%2}")
                           .arg(event->position().x())
                           .arg(event->position().y()));
        }
    }

    void mouseReleaseEvent(QMouseEvent* event) override {
        QGraphicsView::mouseReleaseEvent(event);
        // Check for moved nodes
        QList<QGraphicsItem*> sel = scene_->selectedItems();
        for (auto* item : sel) {
            auto* nodeItem = dynamic_cast<CanvasNodeItem*>(item);
            if (nodeItem && !nodeItem->pos().isNull()) {
                QRectF r = nodeItem->sceneBoundingRect();
                emitEvent("node_moved",
                           QString("{\"id\":\"%1\",\"x\":%2,\"y\":%3,\"width\":%4,\"height\":%5}")
                               .arg(nodeItem->nodeId())
                               .arg(r.x()).arg(r.y())
                               .arg(r.width()).arg(r.height()));
            }
        }
        // Update edges after node movements
        for (auto& ep : edges_) {
            ep.second->updatePosition();
        }
    }

    void mouseDoubleClickEvent(QMouseEvent* event) override {
        QGraphicsView::mouseDoubleClickEvent(event);
        QGraphicsItem* item = itemAt(event->pos());
        auto* nodeItem = dynamic_cast<CanvasNodeItem*>(item);
        if (nodeItem) {
            emitEvent("node_double_clicked",
                       QString("{\"id\":\"%1\"}").arg(nodeItem->nodeId()));
        }
    }

    void wheelEvent(QWheelEvent* event) override {
        // Zoom with Ctrl+scroll
        if (event->modifiers() & Qt::ControlModifier) {
            double factor = event->angleDelta().y() > 0 ? 1.15 : 1.0 / 1.15;
            scale(factor, factor);
            event->accept();
        } else {
            QGraphicsView::wheelEvent(event);
        }
    }

private:
    void emitEvent(const char* type, const QString& data) {
        QMutexLocker lock(&callback_mutex_);
        if (callback_) {
            QByteArray utf8 = data.toUtf8();
            callback_(type, utf8.constData());
        }
    }

    void updateEdgesForNode(CanvasNodeItem* node) {
        for (auto& ep : edges_) {
            if (ep.second->sourceNode() == node || ep.second->targetNode() == node) {
                ep.second->updatePosition();
            }
        }
    }

    void updateAllEdges() {
        for (auto& ep : edges_) {
            ep.second->updatePosition();
        }
    }

    QGraphicsScene* scene_;
    QMap<QString, CanvasNodeItem*> nodes_;
    QMap<QString, CanvasEdgeItem*> edges_;
    CanvasCallback callback_;
    QMutex callback_mutex_;
    double grid_layout_spacing_;
};

// ============================================================================
// Global application state
// ============================================================================

static QApplication* g_app = nullptr;
static int g_argc = 1;
static char g_appName[] = "devnote_qt";
static char* g_argv[] = { g_appName, nullptr };

// ============================================================================
// C ABI Implementation
// ============================================================================

extern "C" {

int devnote_qt_init(int argc, char* argv[]) {
    if (g_app != nullptr) return 0; // already initialized
    // QApplication requires non-const argc
    g_argc = argc > 0 ? argc : 1;
    g_app = new QApplication(g_argc, (argc > 0) ? argv : g_argv);
    return 0;
}

void devnote_qt_destroy() {
    delete g_app;
    g_app = nullptr;
}

void* devnote_qt_create_canvas(void* parent_window_handle) {
    QWidget* parent = nullptr;
    if (parent_window_handle) {
        parent = QWidget::createWindowContainer(
            QWindow::fromWinId(reinterpret_cast<WId>(parent_window_handle)));
    }
    auto* canvas = new CanvasWidget(parent);
    canvas->show();
    return static_cast<void*>(canvas);
}

void devnote_qt_destroy_canvas(void* canvas_handle) {
    delete static_cast<CanvasWidget*>(canvas_handle);
}

void devnote_qt_canvas_add_node(void* canvas_handle, const char* node_id,
                                 const char* content, double x, double y,
                                 double w, double h) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->addNode(QString::fromUtf8(node_id),
                QString::fromUtf8(content ? content : ""),
                x, y, w, h);
}

void devnote_qt_canvas_update_node(void* canvas_handle, const char* node_id,
                                    double x, double y, double w, double h) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->updateNode(QString::fromUtf8(node_id), x, y, w, h);
}

void devnote_qt_canvas_remove_node(void* canvas_handle, const char* node_id) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->removeNode(QString::fromUtf8(node_id));
}

void devnote_qt_canvas_add_edge(void* canvas_handle, const char* edge_id,
                                 const char* source_id, const char* target_id,
                                 const char* label) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->addEdge(QString::fromUtf8(edge_id),
                QString::fromUtf8(source_id),
                QString::fromUtf8(target_id),
                QString::fromUtf8(label ? label : ""));
}

void devnote_qt_canvas_remove_edge(void* canvas_handle, const char* edge_id) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->removeEdge(QString::fromUtf8(edge_id));
}

void devnote_qt_canvas_clear(void* canvas_handle) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->clearCanvas();
}

void devnote_qt_canvas_set_callback(void* canvas_handle,
                                     void (*callback)(const char*, const char*)) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->setCallback(callback);
}

void devnote_qt_canvas_set_zoom(void* canvas_handle, double zoom) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->setZoom(zoom);
}

void devnote_qt_canvas_fit_all(void* canvas_handle) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->fitAll();
}

void devnote_qt_canvas_export_image(void* canvas_handle, const char* path) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->exportImage(QString::fromUtf8(path));
}

void devnote_qt_canvas_load_json(void* canvas_handle, const char* json) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    cw->loadJson(QString::fromUtf8(json));
}

char* devnote_qt_canvas_save_json(void* canvas_handle) {
    auto* cw = static_cast<CanvasWidget*>(canvas_handle);
    QString json = cw->saveJson();
    QByteArray utf8 = json.toUtf8();
    char* result = static_cast<char*>(std::malloc(utf8.size() + 1));
    if (result) {
        std::memcpy(result, utf8.constData(), utf8.size());
        result[utf8.size()] = '\0';
    }
    return result;
}

void devnote_qt_free_string(char* s) {
    std::free(s);
}

} // extern "C"

#include "qt_bridge.moc"