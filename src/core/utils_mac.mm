/*
 * MIT License
 *
 * Copyright (C) 2022 by wangwenx190 (Yuhang Zhao)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "utils.h"
#include "framelessmanager.h"
#include <QtCore/qdebug.h>
#include <QtCore/qhash.h>
#include <QtCore/qmutex.h>
#include <QtCore/qcoreapplication.h>
#include <QtGui/qwindow.h>
#include <objc/runtime.h>
#include <AppKit/AppKit.h>

QT_BEGIN_NAMESPACE
[[nodiscard]] Q_GUI_EXPORT QColor qt_mac_toQColor(const NSColor *color);
QT_END_NAMESPACE

FRAMELESSHELPER_BEGIN_NAMESPACE

using namespace Global;

class NSWindowProxy : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(NSWindowProxy)

public:
    explicit NSWindowProxy(QWindow *qtWindow, NSWindow *macWindow, QObject *parent = nil) : QObject(parent)
    {
        Q_ASSERT(qtWindow);
        Q_ASSERT(macWindow);
        Q_ASSERT(!instances.contains(macWindow));
        if (!qtWindow || !macWindow || instances.contains(macWindow)) {
            return;
        }
        qwindow = qtWindow;
        nswindow = macWindow;
        instances.insert(macWindow, this);
        saveState();
        if (!windowClass) {
            windowClass = [nswindow class];
            Q_ASSERT(windowClass);
            replaceImplementations();
        }
    }

    ~NSWindowProxy() override
    {
        instances.remove(nswindow);
        if (instances.count() <= 0) {
            restoreImplementations();
            windowClass = nil;
        }
        restoreState();
        nswindow = nil;
    }

public Q_SLOTS:
    void saveState()
    {
        oldStyleMask = nswindow.styleMask;
        oldTitlebarAppearsTransparent = nswindow.titlebarAppearsTransparent;
        oldTitleVisibility = nswindow.titleVisibility;
        oldHasShadow = nswindow.hasShadow;
        oldShowsToolbarButton = nswindow.showsToolbarButton;
        oldMovableByWindowBackground = nswindow.movableByWindowBackground;
        oldMovable = nswindow.movable;
        oldCloseButtonVisible = ![nswindow standardWindowButton:NSWindowCloseButton].hidden;
        oldMiniaturizeButtonVisible = ![nswindow standardWindowButton:NSWindowMiniaturizeButton].hidden;
        oldZoomButtonVisible = ![nswindow standardWindowButton:NSWindowZoomButton].hidden;
    }

    void restoreState()
    {
        nswindow.styleMask = oldStyleMask;
        nswindow.titlebarAppearsTransparent = oldTitlebarAppearsTransparent;
        nswindow.titleVisibility = oldTitleVisibility;
        nswindow.hasShadow = oldHasShadow;
        nswindow.showsToolbarButton = oldShowsToolbarButton;
        nswindow.movableByWindowBackground = oldMovableByWindowBackground;
        nswindow.movable = oldMovable;
        [nswindow standardWindowButton:NSWindowCloseButton].hidden = !oldCloseButtonVisible;
        [nswindow standardWindowButton:NSWindowMiniaturizeButton].hidden = !oldMiniaturizeButtonVisible;
        [nswindow standardWindowButton:NSWindowZoomButton].hidden = !oldZoomButtonVisible;
    }

    void replaceImplementations()
    {
        Method method = class_getInstanceMethod(windowClass, @selector(setStyleMask:));
        Q_ASSERT(method);
        oldSetStyleMask = reinterpret_cast<setStyleMaskPtr>(method_setImplementation(method, reinterpret_cast<IMP>(setStyleMask)));
        Q_ASSERT(oldSetStyleMask);

        method = class_getInstanceMethod(windowClass, @selector(setTitlebarAppearsTransparent:));
        Q_ASSERT(method);
        oldSetTitlebarAppearsTransparent = reinterpret_cast<setTitlebarAppearsTransparentPtr>(method_setImplementation(method, reinterpret_cast<IMP>(setTitlebarAppearsTransparent)));
        Q_ASSERT(oldSetTitlebarAppearsTransparent);

        method = class_getInstanceMethod(windowClass, @selector(canBecomeKeyWindow));
        Q_ASSERT(method);
        oldCanBecomeKeyWindow = reinterpret_cast<canBecomeKeyWindowPtr>(method_setImplementation(method, reinterpret_cast<IMP>(canBecomeKeyWindow)));
        Q_ASSERT(oldCanBecomeKeyWindow);

        method = class_getInstanceMethod(windowClass, @selector(canBecomeMainWindow));
        Q_ASSERT(method);
        oldCanBecomeMainWindow = reinterpret_cast<canBecomeMainWindowPtr>(method_setImplementation(method, reinterpret_cast<IMP>(canBecomeMainWindow)));
        Q_ASSERT(oldCanBecomeMainWindow);

        method = class_getInstanceMethod(windowClass, @selector(sendEvent:));
        Q_ASSERT(method);
        oldSendEvent = reinterpret_cast<sendEventPtr>(method_setImplementation(method, reinterpret_cast<IMP>(sendEvent)));
        Q_ASSERT(oldSendEvent);
    }

    void restoreImplementations()
    {
        Method method = class_getInstanceMethod(windowClass, @selector(setStyleMask:));
        Q_ASSERT(method);
        method_setImplementation(method, reinterpret_cast<IMP>(oldSetStyleMask));
        oldSetStyleMask = nil;

        method = class_getInstanceMethod(windowClass, @selector(setTitlebarAppearsTransparent:));
        Q_ASSERT(method);
        method_setImplementation(method, reinterpret_cast<IMP>(oldSetTitlebarAppearsTransparent));
        oldSetTitlebarAppearsTransparent = nil;

        method = class_getInstanceMethod(windowClass, @selector(canBecomeKeyWindow));
        Q_ASSERT(method);
        method_setImplementation(method, reinterpret_cast<IMP>(oldCanBecomeKeyWindow));
        oldCanBecomeKeyWindow = nil;

        method = class_getInstanceMethod(windowClass, @selector(canBecomeMainWindow));
        Q_ASSERT(method);
        method_setImplementation(method, reinterpret_cast<IMP>(oldCanBecomeMainWindow));
        oldCanBecomeMainWindow = nil;

        method = class_getInstanceMethod(windowClass, @selector(sendEvent:));
        Q_ASSERT(method);
        method_setImplementation(method, reinterpret_cast<IMP>(oldSendEvent));
        oldSendEvent = nil;
    }

    void setSystemTitleBarVisible(const bool visible)
    {
        NSView * const nsview = [nswindow contentView];
        Q_ASSERT(nsview);
        if (!nsview) {
            return;
        }
        nsview.wantsLayer = YES;
        nswindow.styleMask |= NSWindowStyleMaskResizable;
        if (visible) {
            nswindow.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
        } else {
            nswindow.styleMask |= NSWindowStyleMaskFullSizeContentView;
        }
        nswindow.titlebarAppearsTransparent = (visible ? NO : YES);
        nswindow.titleVisibility = (visible ? NSWindowTitleVisible : NSWindowTitleHidden);
        nswindow.hasShadow = YES;
        nswindow.showsToolbarButton = NO;
        nswindow.movableByWindowBackground = NO;
        nswindow.movable = NO;
        [nswindow standardWindowButton:NSWindowCloseButton].hidden = (visible ? NO : YES);
        [nswindow standardWindowButton:NSWindowMiniaturizeButton].hidden = (visible ? NO : YES);
        [nswindow standardWindowButton:NSWindowZoomButton].hidden = (visible ? NO : YES);
    }

    void setBlurBehindWindowEnabled(const bool enable)
    {
        if (enable) {
            if (blurEffect) {
                return;
            }
            NSView * const view = [nswindow contentView];
#if 1
            const Class visualEffectViewClass = NSClassFromString(@"NSVisualEffectView");
            if (!visualEffectViewClass) {
                return;
            }
            NSVisualEffectView * const blurView = [[visualEffectViewClass alloc] initWithFrame:view.bounds];
#else
            NSVisualEffectView * const blurView = [[NSVisualEffectView alloc] initWithFrame:view.bounds];
#endif
            blurView.material = NSVisualEffectMaterialUnderWindowBackground;
            blurView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
            blurView.state = NSVisualEffectStateFollowsWindowActiveState;
            const NSView * const parent = [view superview];
            [parent addSubview:blurView positioned:NSWindowBelow relativeTo:view];
            blurEffect = blurView;
            updateBlurTheme();
            updateBlurSize();
            connect(FramelessManager::instance(),
                &FramelessManager::systemThemeChanged, this, &NSWindowProxy::updateBlurTheme);
            connect(qwindow, &QWindow::widthChanged, this, &NSWindowProxy::updateBlurSize);
            connect(qwindow, &QWindow::heightChanged, this, &NSWindowProxy::updateBlurSize);
        } else {
            if (!blurEffect) {
                return;
            }
            if (widthChangeConnection) {
                disconnect(widthChangeConnection);
                widthChangeConnection = {};
            }
            if (heightChangeConnection) {
                disconnect(heightChangeConnection);
                heightChangeConnection = {};
            }
            if (themeChangeConnection) {
                disconnect(themeChangeConnection);
                themeChangeConnection = {};
            }
            [blurEffect removeFromSuperview];
            blurEffect = nil;
        }
    }

    void updateBlurSize()
    {
        if (!blurEffect) {
            return;
        }
        const NSView * const view = [nswindow contentView];
        blurEffect.frame = view.frame;
    }

    void updateBlurTheme()
    {
        if (!blurEffect) {
            return;
        }
        const auto view = static_cast<NSVisualEffectView *>(blurEffect);
        if (Utils::shouldAppsUseDarkMode()) {
            view.appearance = [NSAppearance appearanceNamed:@"NSAppearanceNameVibrantDark"];
        } else {
            view.appearance = [NSAppearance appearanceNamed:@"NSAppearanceNameVibrantLight"];
        }
    }

private:
    static BOOL canBecomeKeyWindow(id obj, SEL sel)
    {
        if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
            return YES;
        }

        if (oldCanBecomeKeyWindow) {
            return oldCanBecomeKeyWindow(obj, sel);
        }

        return YES;
    }

    static BOOL canBecomeMainWindow(id obj, SEL sel)
    {
        if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
            return YES;
        }

        if (oldCanBecomeMainWindow) {
            return oldCanBecomeMainWindow(obj, sel);
        }

        return YES;
    }

    static void setStyleMask(id obj, SEL sel, NSWindowStyleMask styleMask)
    {
        if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
            styleMask |= NSWindowStyleMaskFullSizeContentView;
        }

        if (oldSetStyleMask) {
            oldSetStyleMask(obj, sel, styleMask);
        }
    }

    static void setTitlebarAppearsTransparent(id obj, SEL sel, BOOL transparent)
    {
        if (instances.contains(reinterpret_cast<NSWindow *>(obj))) {
            transparent = YES;
        }

        if (oldSetTitlebarAppearsTransparent) {
            oldSetTitlebarAppearsTransparent(obj, sel, transparent);
        }
    }

    static void sendEvent(id obj, SEL sel, NSEvent *event)
    {
        if (oldSendEvent) {
            oldSendEvent(obj, sel, event);
        }

        const auto nswindow = reinterpret_cast<NSWindow *>(obj);
        if (!instances.contains(nswindow)) {
            return;
        }

        NSWindowProxy * const proxy = instances[nswindow];
        if (event.type == NSEventTypeLeftMouseDown) {
            proxy->lastMouseDownEvent = event;
            QCoreApplication::processEvents();
            proxy->lastMouseDownEvent = nil;
        }
    }

private:
    QWindow *qwindow = nil;
    NSWindow *nswindow = nil;
    NSEvent *lastMouseDownEvent = nil;
    NSView *blurEffect = nil;

    NSWindowStyleMask oldStyleMask = 0;
    BOOL oldTitlebarAppearsTransparent = NO;
    BOOL oldHasShadow = NO;
    BOOL oldShowsToolbarButton = NO;
    BOOL oldMovableByWindowBackground = NO;
    BOOL oldMovable = NO;
    BOOL oldCloseButtonVisible = NO;
    BOOL oldMiniaturizeButtonVisible = NO;
    BOOL oldZoomButtonVisible = NO;
    NSWindowTitleVisibility oldTitleVisibility = NSWindowTitleVisible;

    QMetaObject::Connection widthChangeConnection = {};
    QMetaObject::Connection heightChangeConnection = {};
    QMetaObject::Connection themeChangeConnection = {};

    static inline QHash<NSWindow *, NSWindowProxy *> instances = {};

    static inline Class windowClass = nil;

    using setStyleMaskPtr = void(*)(id, SEL, NSWindowStyleMask);
    static inline setStyleMaskPtr oldSetStyleMask = nil;

    using setTitlebarAppearsTransparentPtr = void(*)(id, SEL, BOOL);
    static inline setTitlebarAppearsTransparentPtr oldSetTitlebarAppearsTransparent = nil;

    using canBecomeKeyWindowPtr = BOOL(*)(id, SEL);
    static inline canBecomeKeyWindowPtr oldCanBecomeKeyWindow = nil;

    using canBecomeMainWindowPtr = BOOL(*)(id, SEL);
    static inline canBecomeMainWindowPtr oldCanBecomeMainWindow = nil;

    using sendEventPtr = void(*)(id, SEL, NSEvent *);
    static inline sendEventPtr oldSendEvent = nil;
};

struct MacUtilsData
{
    QMutex mutex;
    QHash<WId, NSWindowProxy *> hash = {};
};

Q_GLOBAL_STATIC(MacUtilsData, g_macUtilsData);

[[nodiscard]] static inline NSWindow *mac_getNSWindow(const WId windowId)
{
    Q_ASSERT(windowId);
    if (!windowId) {
        return nil;
    }
    const auto nsview = reinterpret_cast<NSView *>(windowId);
    Q_ASSERT(nsview);
    if (!nsview) {
        return nil;
    }
    return [nsview window];
}

[[nodiscard]] static inline NSWindowProxy *ensureWindowProxy(const WId windowId)
{
    Q_ASSERT(windowId);
    if (!windowId) {
        return nil;
    }
    QMutexLocker locker(&g_macUtilsData()->mutex);
    if (!g_macUtilsData()->hash.contains(windowId)) {
        QWindow * const qwindow = Utils::findWindow(windowId);
        Q_ASSERT(qwindow);
        if (!qwindow) {
            return nil;
        }
        NSWindow * const nswindow = mac_getNSWindow(windowId);
        Q_ASSERT(nswindow);
        if (!nswindow) {
            return nil;
        }
        const auto proxy = new NSWindowProxy(qwindow, nswindow);
        g_macUtilsData()->hash.insert(windowId, proxy);
    }
    return g_macUtilsData()->hash.value(windowId);
}

SystemTheme Utils::getSystemTheme()
{
    // ### TODO: how to detect high contrast mode on macOS?
    return (shouldAppsUseDarkMode() ? SystemTheme::Dark : SystemTheme::Light);
}

void Utils::setSystemTitleBarVisible(const WId windowId, const bool visible)
{
    Q_ASSERT(windowId);
    if (!windowId) {
        return;
    }
    NSWindowProxy * const proxy = ensureWindowProxy(windowId);
    proxy->setSystemTitleBarVisible(visible);
}

void Utils::startSystemMove(QWindow *window, const QPoint &globalPos)
{
    Q_ASSERT(window);
    if (!window) {
        return;
    }
#if (QT_VERSION >= QT_VERSION_CHECK(5, 15, 0))
    Q_UNUSED(globalPos);
    window->startSystemMove();
#else
    const NSWindow * const nswindow = mac_getNSWindow(window->winId());
    Q_ASSERT(nswindow);
    if (!nswindow) {
        return;
    }
    const CGEventRef clickDown = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown,
                         CGPointMake(globalPos.x(), globalPos.y()), kCGMouseButtonLeft);
    NSEvent * const nsevent = [NSEvent eventWithCGEvent:clickDown];
    Q_ASSERT(nsevent);
    if (!nsevent) {
        CFRelease(clickDown);
        return;
    }
    [nswindow performWindowDragWithEvent:nsevent];
    CFRelease(clickDown);
#endif
}

void Utils::startSystemResize(QWindow *window, const Qt::Edges edges, const QPoint &globalPos)
{
    Q_ASSERT(window);
    if (!window) {
        return;
    }
    if (edges == Qt::Edges{}) {
        return;
    }
#if (QT_VERSION >= QT_VERSION_CHECK(5, 15, 0))
    Q_UNUSED(globalPos);
    // Actually Qt doesn't implement this function, it will do nothing and always returns false.
    window->startSystemResize(edges);
#else
    // ### TODO
    Q_UNUSED(globalPos);
#endif
}

QColor Utils::getControlsAccentColor()
{
    return qt_mac_toQColor([NSColor controlAccentColor]);
}

bool Utils::isTitleBarColorized()
{
    return false;
}

bool Utils::shouldAppsUseDarkMode_macos()
{
#if QT_MACOS_PLATFORM_SDK_EQUAL_OR_ABOVE(__MAC_10_14)
    if (__builtin_available(macOS 10.14, *)) {
        const auto appearance = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
                                    @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [appearance isEqualToString:NSAppearanceNameDarkAqua];
    }
#endif
    return false;
}

bool Utils::setBlurBehindWindowEnabled(const WId windowId, const BlurMode mode, const QColor &color)
{
    Q_UNUSED(color);
    Q_ASSERT(windowId);
    if (!windowId) {
        return false;
    }
    const BlurMode blurMode = [mode]() -> BlurMode {
        if ((mode == BlurMode::Disable) || (mode == BlurMode::Default)) {
            return mode;
        }
        qWarning() << "The BlurMode::Windows_* enum values are not supported on macOS.";
        return BlurMode::Default;
    }();
    NSWindowProxy * const proxy = ensureWindowProxy(windowId);
    proxy->setBlurBehindWindowEnabled(blurMode == BlurMode::Default);
    return true;
}

FRAMELESSHELPER_END_NAMESPACE

#include "utils_mac.moc"
