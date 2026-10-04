#if os(tvOS)
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
                .focusSection()
        }
    }
}

/// An invisible area that sends focus to the tab bar (on tvOS the sidebar's
/// tab button). There's no API to open the sidebar; a focus guide pointing
/// at the tab bar is the idiomatic way to let Up reach it.
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

        func refresh() {
            guard let tabs = Self.tabBarController(from: window?.rootViewController) else { guide.isEnabled = false; return }
            guide.isEnabled = true
            guide.preferredFocusEnvironments = [tabs.tabBar]
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
