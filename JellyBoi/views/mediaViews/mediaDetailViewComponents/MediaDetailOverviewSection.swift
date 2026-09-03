//
//  MediaDetailOverviewSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors

extension MediaDetailView {

    func overviewSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overview)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.85))
                .lineLimit(isOverviewExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: isOverviewExpanded)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    if !isOverviewExpanded { overviewLimitedHeight = h }
                }
                .background(
                    Text(overview)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            overviewFullHeight = $0
                        }
                )
                .mask {
                    if isDescriptionTruncated && !isOverviewExpanded {
                        VStack(spacing: 0) {
                            Color.black

                            HStack(spacing: 0) {
                                Color.black

                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(width: 80, height: moreButtonHeight)
                            }
                            .frame(height: moreButtonHeight)
                        }
                    } else {
                        Color.black
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isDescriptionTruncated && !isOverviewExpanded {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isOverviewExpanded = true
                            }
                        } label: {
                            Text("more")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.5))
                                .padding(.leading, 32)
                        }
                        .buttonStyle(.plain)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newHeight in
                            moreButtonHeight = newHeight
                        }
                    }
                }

            if isDescriptionTruncated && isOverviewExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isOverviewExpanded = false
                    }
                } label: {
                    Text("less")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
