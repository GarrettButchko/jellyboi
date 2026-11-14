//
//  TabPageHeader.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI

/// A pinned row of controls that sits directly below the native navigation bar.
///
/// The page title lives in the navigation bar, so this container only hosts
/// supplementary controls (search field, filter picker) and reports its height
/// so hosts can inset their scroll content beneath it.
struct TabPageHeader<Content: View>: View {
    @Binding var headerHeight: CGFloat
    let content: Content

    init(
        headerHeight: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self._headerHeight = headerHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 12)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                // Report the real height so the scroll view can reserve exactly
                // enough room instead of relying on a hard-coded inset.
                guard abs(headerHeight - newHeight) > 0.5 else { return }
                headerHeight = newHeight
            }
    }
}
