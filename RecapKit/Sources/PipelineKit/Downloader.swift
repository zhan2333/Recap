//
//  Downloader.swift
//  PipelineKit
//
//  Created by Rio on 2026/8/19.
//

import Foundation

/// Streams a media URL to disk with the headers cloud-classroom servers
/// require (UA + Referer), always bypassing the system proxy — domestic
/// servers reject or throttle proxied connections.
public struct Downloader {

    public enum DownloadError: Error, LocalizedError {
        case badResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let code): "Server responded with HTTP \(code)"
            }
        }
    }

    public struct Request {
        public var url: URL
        public var referer: String?
        public var userAgent: String

        public init(
            url: URL,
            referer: String? = nil,
            userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
        ) {
            self.url = url
            self.referer = referer
            self.userAgent = userAgent
        }
    }

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:] // force direct connection
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config)
    }

    /// Downloads to `destination`, reporting fractional progress when the
    /// server provides a Content-Length. Skips work if the file already
    /// exists and is non-trivial (same guard the shell pipeline used).
    public func download(
        _ request: Request,
        to destination: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if let size = try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int,
           size > 50 * 1024 * 1024 {
            onProgress?(1)
            return
        }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.setValue(request.userAgent, forHTTPHeaderField: "User-Agent")
        if let referer = request.referer {
            urlRequest.setValue(referer, forHTTPHeaderField: "Referer")
        }

        let (bytes, response) = try await session.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.badResponse(http.statusCode)
        }

        let expected = response.expectedContentLength // -1 if unknown
        let tempURL = destination.appendingPathExtension("part")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    onProgress?(Double(written) / Double(expected))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        try handle.close()

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        onProgress?(1)
    }
}
