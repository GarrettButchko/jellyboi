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
    var isCollapsed: Bool = false
    var scrollOffset: CGFloat = 0
    @Binding var headerHeight: CGFloat
    let content: Content
    var showGradient: Bool = true
    var showBackButton: Bool = false
    private var isTitleHidden: Bool { isCollapsed || scrollOffset > 20 }

    init(
        title: String,
        isCollapsed: Bool = false,
        scrollOffset: CGFloat = 0,
        headerHeight: Binding<CGFloat> = .constant(0),
        showGradient: Bool = true,
        showBackButton: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.scrollOffset = scrollOffset
        self._headerHeight = headerHeight
        self.showGradient = showGradient
        self.showBackButton = showBackButton
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isTitleHidden {
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
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Color.clear
                .frame(height: 0)
            content
                .padding(.top, isTitleHidden ? 0 : 16)
        }
        .padding(.vertical, 16)
        .animation(.smooth(duration: 0.25), value: isTitleHidden)
    }
}

extension TabPageHeader where Content == EmptyView {
    init(
        title: String,
        isCollapsed: Bool = false,
        scrollOffset: CGFloat = 0,
        headerHeight: Binding<CGFloat> = .constant(0),
        showGradient: Bool = true,
        showBackButton: Bool = false
    ) {
        self.init(
            title: title,
            isCollapsed: isCollapsed,
            scrollOffset: scrollOffset,
            headerHeight: headerHeight,
            showGradient: showGradient,
            showBackButton: showBackButton
        ) { EmptyView() }
    }
}
