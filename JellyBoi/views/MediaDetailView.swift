//
//  MediaDetailView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaDetailView: View {
    let item: BaseItemDto

    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                posterImage
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.mainOpp.opacity(0.08), lineWidth: 1)
                    }
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name ?? "")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)

                    if let year = item.productionYear {
                        Text(String(year))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }

                    if let overview = item.overview {
                        Text(overview)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.bg.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            backButton
                .padding(.leading, 16)
                .padding(.top, 4)
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let client = serverViewModel.client,
           let id = item.id,
           let url = client.url(with: Paths.getItemImage(
               itemID: id,
               imageType: "Primary",
               parameters: .init(maxWidth: 600, quality: 90)
           )) {
            WebImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.sub
            }
        } else {
            Color.sub
        }
    }
}

#Preview {
    MediaDetailView(item: BaseItemDto(name: "Sample Item"))
}
