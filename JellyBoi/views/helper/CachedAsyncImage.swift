//
//  CachedAsyncImage.swift
//  JellyBoi
//
//  Created by Lorenzo Fiamingo on 04/11/20.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension URLCache {
    public static let imageCache = URLCache(memoryCapacity: 512_000_000, diskCapacity: 10_000_000_000)
}

/// A view that asynchronously loads, caches, and displays an image.
/// When the image is already cached in `urlCache`, it renders synchronously
/// on the very first frame to prevent flickering during zoom hero transitions.
public struct CachedAsyncImage<Content>: View where Content: View {

    @State private var phase: AsyncImagePhase

    private let urlRequest: URLRequest?
    private let urlSession: URLSession
    private let scale: CGFloat
    private let transaction: Transaction
    private let onLoaded: ((CGSize) -> Void)?
    private let content: (AsyncImagePhase) -> Content

    public var body: some View {
        content(phase)
            .task(id: urlRequest, load)
    }

    public init(
        url: URL?,
        urlCache: URLCache = .imageCache,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        onLoaded: ((CGSize) -> Void)? = nil,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        let urlRequest = url == nil ? nil : URLRequest(url: url!)
        self.init(
            urlRequest: urlRequest,
            urlCache: urlCache,
            scale: scale,
            transaction: transaction,
            onLoaded: onLoaded,
            content: content
        )
    }

    public init(
        urlRequest: URLRequest?,
        urlCache: URLCache = .imageCache,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        onLoaded: ((CGSize) -> Void)? = nil,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        self.urlRequest = urlRequest
        self.urlSession = URLSession(configuration: configuration)
        self.scale = scale
        self.transaction = transaction
        self.onLoaded = onLoaded
        self.content = content

        self._phase = State(wrappedValue: .empty)
        do {
            if let urlRequest = urlRequest, let (image, size) = try Self.cachedImage(from: urlRequest, cache: urlCache, scale: scale) {
                self._phase = State(wrappedValue: .success(image))
                onLoaded?(size)
            }
        } catch {
            self._phase = State(wrappedValue: .failure(error))
        }
    }

    @Sendable
    private func load() async {
        do {
            if let urlRequest = urlRequest {
                let (image, size, metrics) = try await remoteImage(from: urlRequest, session: urlSession)
                onLoaded?(size)
                if metrics.transactionMetrics.last?.resourceFetchType == .localCache {
                    phase = .success(image)
                } else {
                    withAnimation(transaction.animation) {
                        phase = .success(image)
                    }
                }
            } else {
                withAnimation(transaction.animation) {
                    phase = .empty
                }
            }
        } catch {
            withAnimation(transaction.animation) {
                phase = .failure(error)
            }
        }
    }

    private struct LoadingError: Error {}

    private func remoteImage(from request: URLRequest, session: URLSession) async throws -> (Image, CGSize, URLSessionTaskMetrics) {
        let (data, _, metrics) = try await session.data(for: request)
        if metrics.redirectCount > 0, let lastResponse = metrics.transactionMetrics.last?.response {
            let requests = metrics.transactionMetrics.map { $0.request }
            requests.forEach(session.configuration.urlCache!.removeCachedResponse)
            let lastCachedResponse = CachedURLResponse(response: lastResponse, data: data)
            session.configuration.urlCache!.storeCachedResponse(lastCachedResponse, for: request)
        }
        let (img, size) = try Self.image(from: data, scale: scale)
        return (img, size, metrics)
    }

    private static func cachedImage(from request: URLRequest, cache: URLCache, scale: CGFloat) throws -> (Image, CGSize)? {
        guard let cachedResponse = cache.cachedResponse(for: request) else { return nil }
        return try image(from: cachedResponse.data, scale: scale)
    }

    private static func image(from data: Data, scale: CGFloat) throws -> (Image, CGSize) {
#if os(macOS)
        if let nsImage = NSImage(data: data) {
            return (Image(nsImage: nsImage), nsImage.size)
        } else {
            throw LoadingError()
        }
#else
        if let uiImage = UIImage(data: data, scale: scale) {
            return (Image(uiImage: uiImage), uiImage.size)
        } else {
            throw LoadingError()
        }
#endif
    }
}

// MARK: - AsyncImageURLSession

private class URLSessionTaskController: NSObject, URLSessionTaskDelegate {
    var metrics: URLSessionTaskMetrics?

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        self.metrics = metrics
    }
}

private extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse, URLSessionTaskMetrics) {
        let controller = URLSessionTaskController()
        let (data, response) = try await data(for: request, delegate: controller)
        return (data, response, controller.metrics!)
    }
}
