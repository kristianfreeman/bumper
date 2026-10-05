#if os(tvOS)
import DesignSystem
import Instrumentation
import SwiftUI
import UIKit

/// The strip above a page's content: Up from the top row lands here. The
/// left half leads to the sidebar (the tab button), the right half to the
/// page's own controls — so Up works from any card, not just the ones
/// directly beneath a target.
struct TopBand<Trailing: View>: View {
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            TabBarFocusGuide()
                .frame(maxWidth: .infinity, minHeight: 90)
            trailing()
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .trailing)
                .tvFocusSection()
        }
    }
}

/// An invisible area that sends focus to the tab bar (on tvOS the sidebar's
/// tab button). There's no API to open the sidebar; a focus guide pointing
/// at the tab bar is the idiomatic way to let Up reach it.
///
/// tvOS 27 only, in effect: on tvOS 26 SwiftUI draws the sidebar itself (no
/// UITabBarController) and the collapsed sidebar has no focusable item at
/// all — only the system's Left and Menu open it — so the guide stays off.
struct TabBarFocusGuide: UIViewRepresentable {
    func makeUIView(context: Context) -> GuideView { GuideView() }
    func updateUIView(_ view: GuideView, context: Context) { view.refresh() }

    final class GuideView: UIView {
        private let guide = UIFocusGuide()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if guide.owningView == nil {
                addLayoutGuide(guide)
                NSLayoutConstraint.activate([
                    guide.leadingAnchor.constraint(equalTo: leadingAnchor),
                    guide.trailingAnchor.constraint(equalTo: trailingAnchor),
                    guide.topAnchor.constraint(equalTo: topAnchor),
                    guide.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            }
            refresh()
        }

        private var retries = 0

        func refresh() {
            guard let tabs = Self.tabBarController(from: window?.rootViewController) else {
                // The tab view's controller can join the hierarchy after this
                // view does: look again shortly (up to ~5 s).
                guide.isEnabled = false
                guard window != nil, retries < 25 else { return }
                retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
                return
            }
            guide.isEnabled = true
            guide.preferredFocusEnvironments = [tabs.tabBar]
            if retries > 0 { TraceFile.write("focus", "sidebar guide found the tab bar after \(retries) tries") }
            retries = 0
        }

        static func tabBarController(from root: UIViewController?) -> UITabBarController? {
            var queue = [root].compactMap { $0 }
            while !queue.isEmpty {
                let vc = queue.removeFirst()
                if let tabs = vc as? UITabBarController { return tabs }
                queue += vc.children
                if let presented = vc.presentedViewController { queue.append(presented) }
            }
            return nil
        }
    }
}
#endif
