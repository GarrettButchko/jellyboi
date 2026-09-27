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
        Binding(
            get: { isExternalBinding ? isExpandedExternal : showSheetInternal },
            set: { newValue in
                if isExternalBinding {
                    isExpandedExternal = newValue
                } else {
                    showSheetInternal = newValue
                }
            }
        )
    }

    private var isDescriptionTruncated: Bool {
        fullHeight > limitedHeight + 1
    }

    init(
        _ text: String,
        sheetTitle: String? = "Overview",
        lineLimit: Int = 3,
        font: Font = .system(.body, design: .rounded),
        textColor: Color = Color.mainOpp.opacity(0.85),
        buttonColor: Color = Color.mainOpp,
        buttonFont: Font = .system(size: 12, weight: .semibold, design: .rounded),
        moreText: String = "more",
        showChevron: Bool = false,
        isExpanded: Binding<Bool>? = nil
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                limitedHeight = h
            }
            .background(
                Text(text)
                    .font(font)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        fullHeight = $0
                    }
            )
            .mask {
                if isDescriptionTruncated {
                    let maskHeight = max(moreButtonSize.height, 24)
                    VStack(spacing: 0) {
                        Color.black

                        HStack(spacing: 0) {
                            Color.black

                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(
                                width: max(80, moreButtonSize.width + 24),
                                height: maskHeight
                            )
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
                        //need this for background to be transparent
                        .presentationBackground {
                            Color.clear
                        }
                        .background(.ultraThinMaterial)
            }
            .onChange(of: text) {
                if !isExternalBinding {
                    showSheetInternal = false
                }
            }
    }

    private var fullTextSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let sheetTitle, !sheetTitle.isEmpty {
                    Text(sheetTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                }

                Spacer()

                Button {
                    isPresentedBinding.wrappedValue = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.mainOpp.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()
                .foregroundStyle(Color.mainOpp.opacity(0.12))

            ScrollView {
                Text(text)
                    .font(font)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
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
