//
//  TabPageHeader.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors

struct TabPageHeader<Content: View>: View {
    let title: String
    let scrollOffset: CGFloat
    @Binding var headerHeight: CGFloat
    let content: Content
    var showGradient: Bool = true
    var showBackButton: Bool = false
    @State private var titleRowHeight: CGFloat = 40
    private var isTitleHidden: Bool { scrollOffset > titleRowHeight }

    init(
        title: String,
        scrollOffset: CGFloat = 0,
        headerHeight: Binding<CGFloat> = .constant(0),
        showGradient: Bool = true,
        showBackButton: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.scrollOffset = scrollOffset
        self._headerHeight = headerHeight
        self.showGradient = showGradient
        self.showBackButton = showBackButton
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isTitleHidden {
                Group{
                    HStack(alignment: .center) {
                        if showBackButton {
                            BackButton()
                                .padding(.leading, -6)
                        }
                        Text(title)
                            .font(.system(size: 35, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        if !showBackButton {
                            ProfileAvatarButton()
                                .padding(.trailing, -20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if h > 0 { titleRowHeight = h }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Color.clear
                .frame(height: 0)
            content
                .padding(.top, isTitleHidden ? 0 : 16)
        }
        .padding(.vertical, 16)
        .animation(.smooth, value: isTitleHidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
            if newHeight > 0 && !isTitleHidden { headerHeight = newHeight }
        }
    }
}

extension TabPageHeader where Content == EmptyView {
    init(
        title: String,
        scrollOffset: CGFloat = 0,
        headerHeight: Binding<CGFloat> = .constant(0),
        showGradient: Bool = true,
        showBackButton: Bool = false
    ) {
        self.init(title: title, scrollOffset: scrollOffset, headerHeight: headerHeight, showGradient: showGradient, showBackButton: showBackButton) { EmptyView() }
    }
}
