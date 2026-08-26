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

    @State private var titleRowHeight: CGFloat = 40
    private var isTitleHidden: Bool { scrollOffset > titleRowHeight }

    init(
        title: String,
        scrollOffset: CGFloat = 0,
        headerHeight: Binding<CGFloat> = .constant(0),
        showGradient: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.scrollOffset = scrollOffset
        self._headerHeight = headerHeight
        self.showGradient = showGradient
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isTitleHidden {
                HStack(alignment: .center) {
                    Text(title)
                        .font(.system(size: 35, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                    Spacer()
                    ProfileAvatarButton()
                        .padding(.trailing, -20)
                }
                .padding(.horizontal, 20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    if h > 0 { titleRowHeight = h }
                }
            }
            Color.clear
                .frame(height: 0)
            content
                .padding(.top, isTitleHidden ? 0 : 16)
        }
        .padding(.vertical, 16)
        .animation(.smooth, value: isTitleHidden)
       // .background {
         //   if showGradient {
           //     LinearGradient(
           //         colors: [Color.bg, Color.bg.opacity(0.8), Color.clear],
             //       startPoint: .top,
             //       endPoint: .bottom
               // )
               // .ignoresSafeArea(edges: .top)
           // }
        //}
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
        showGradient: Bool = true
    ) {
        self.init(title: title, scrollOffset: scrollOffset, headerHeight: headerHeight, showGradient: showGradient) { EmptyView() }
    }
}
