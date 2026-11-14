//
//  ExpandableText.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/22/26.
//

import SwiftUI
import BaseColors

struct ExpandableText: View {
    let text: String
    var sheetTitle: String? = "Overview"
    var lineLimit: Int = 3
    var font: Font = .system(.body, design: .rounded)
    var textColor: Color = Color.mainOpp.opacity(0.85)
    var buttonColor: Color = Color.mainOpp
    var buttonFont: Font = .system(size: 12, weight: .semibold, design: .rounded)
    var moreText: String = "more"
    var showChevron: Bool = false

    @Binding private var isExpandedExternal: Bool
    private let isExternalBinding: Bool

    @State private var showSheetInternal = false
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var moreButtonSize: CGSize = .zero

    private var isPresentedBinding: Binding<Bool> {
        if isExternalBinding {
            return $isExpandedExternal
        } else {
            return $showSheetInternal
        }
    }

    private var isDescriptionTruncated: Bool {
        limitedHeight > 0 && fullHeight > (limitedHeight + 2)
    }

    init(
        _ text: String,
        isExpanded: Binding<Bool>? = nil,
        sheetTitle: String? = "Overview",
        lineLimit: Int = 3,
        font: Font = .system(.body, design: .rounded),
        textColor: Color = Color.mainOpp.opacity(0.85),
        buttonColor: Color = Color.mainOpp,
        buttonFont: Font = .system(size: 12, weight: .semibold, design: .rounded),
        moreText: String = "more",
        showChevron: Bool = false
    ) {
        self.text = text
        self.sheetTitle = sheetTitle
        self.lineLimit = lineLimit
        self.font = font
        self.textColor = textColor
        self.buttonColor = buttonColor
        self.buttonFont = buttonFont
        self.moreText = moreText
        self.showChevron = showChevron

        if let isExpanded {
            self._isExpandedExternal = isExpanded
            self.isExternalBinding = true
        } else {
            self._isExpandedExternal = .constant(false)
            self.isExternalBinding = false
        }
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(textColor)
            .lineLimit(lineLimit)
            .background {
                Text(text)
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        fullHeight = newHeight
                    }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                limitedHeight = newHeight
            }
            .mask {
                if isDescriptionTruncated {
                    let maskWidth = max(moreButtonSize.width + 16, 80)
                    let maskHeight = max(moreButtonSize.height + 16, 28)

                    VStack(spacing: 0) {
                        Color.black

                        HStack(spacing: 0) {
                            Color.black

                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: maskWidth)
                        }
                        .frame(height: maskHeight)
                    }
                } else {
                    Color.black
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isDescriptionTruncated {
                    Button {
                        isPresentedBinding.wrappedValue = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(moreText)
                            if showChevron {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .font(buttonFont)
                        .foregroundStyle(buttonColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { newSize in
                        moreButtonSize = newSize
                    }
                }
            }
            .sheet(isPresented: isPresentedBinding) {
                fullTextSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.clear)
            }
            .onChange(of: text) {
                if !isExternalBinding {
                    showSheetInternal = false
                }
            }
    }

    private var fullTextSheet: some View {
        ScrollView {
            Text(text)
                .font(font)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 24)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        ExpandableText("This is a short text that doesn't need truncation.")

        ExpandableText(
            "This is a much longer overview text meant to demonstrate the truncation and popup sheet behavior. When the text exceeds the specified line limit, a subtle gradient fade mask is applied along with a trailing capsule glass 'more' button. Tapping 'more' presents a translucent material bottom sheet with a drag indicator and the full scrollable text.",
            sheetTitle: "Overview",
            lineLimit: 3
        )
    }
    .padding(20)
}
