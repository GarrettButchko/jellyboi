//
//  RemuxAspectRatioHelper.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/14/26.
//

import Foundation
import LoggingKit
import Libavformat
import Libavcodec
import Libavutil

enum RemuxAspectRatioHelper {
    /// Resolves the effective Sample Aspect Ratio (SAR) for the video track by checking:
    /// 1. Jellyfin targetAspectRatio string (e.g. "16:9", "1.78:1")
    /// 2. Container-level SAR detection (matroskadec DisplayWidth / DisplayHeight, etc.)
    /// 3. Stream-level SAR
    /// 4. Codec parameters SAR
    /// 5. Fallback to 1:1 square pixels
    static func resolveEffectiveSAR(
        inCtx: UnsafeMutablePointer<AVFormatContext>,
        inVideoStream: UnsafeMutablePointer<AVStream>,
        targetAspectRatio: String?
    ) -> AVRational {
        let cp = inVideoStream.pointee.codecpar.pointee
        let width = cp.width
        let height = cp.height
        let codedDAR = height > 0 ? (Double(width) / Double(height)) : 1.0

        // 1. Try parsing targetAspectRatio (e.g. from Jellyfin metadata "16:9", "1.78:1")
        if let targetAspect = targetAspectRatio?.trimmingCharacters(in: .whitespacesAndNewlines), !targetAspect.isEmpty {
            var targetDAR: Double? = nil
            if targetAspect.contains(":") {
                let parts = targetAspect.split(separator: ":")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    targetDAR = num / den
                }
            } else if targetAspect.contains("/") {
                let parts = targetAspect.split(separator: "/")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    targetDAR = num / den
                }
            } else if let val = Double(targetAspect), val > 0 {
                targetDAR = val
            }

            if let dar = targetDAR, width > 0, height > 0 {
                let diff = abs(dar - codedDAR) / codedDAR
                if diff > 0.01 {
                    var sarNum: Int32 = 0
                    var sarDen: Int32 = 0
                    let factor = 100_000.0
                    let num64 = Int64(round(dar * Double(height) * factor))
                    let den64 = Int64(round(Double(width) * factor))
                    av_reduce(&sarNum, &sarDen, num64, den64, 1024)
                    if sarNum > 0 && sarDen > 0 {
                        AppLogger.info("Calculated SAR \(sarNum):\(sarDen) from target aspect ratio '\(targetAspect)' (DAR: \(String(format: "%.3f", dar)), coded DAR: \(String(format: "%.3f", codedDAR)))")
                        return AVRational(num: sarNum, den: sarDen)
                    }
                }
            }
        }

        // 2. Try FFmpeg's container-level SAR detection (matroskadec DisplayWidth / DisplayHeight, etc.)
        let guessed = av_guess_sample_aspect_ratio(inCtx, inVideoStream, nil)
        if guessed.num > 0 && guessed.den > 0 && guessed.num != guessed.den {
            AppLogger.info("Detected container SAR \(guessed.num):\(guessed.den) via av_guess_sample_aspect_ratio")
            return guessed
        }

        // 3. Try stream-level SAR
        let stSAR = inVideoStream.pointee.sample_aspect_ratio
        if stSAR.num > 0 && stSAR.den > 0 && stSAR.num != stSAR.den {
            AppLogger.info("Using stream SAR \(stSAR.num):\(stSAR.den)")
            return stSAR
        }

        // 4. Try codecpar-level SAR
        let cpSAR = inVideoStream.pointee.codecpar.pointee.sample_aspect_ratio
        if cpSAR.num > 0 && cpSAR.den > 0 && cpSAR.num != cpSAR.den {
            AppLogger.info("Using codecpar SAR \(cpSAR.num):\(cpSAR.den)")
            return cpSAR
        }

        // 5. Default to square pixels or whatever stream has
        return (stSAR.num > 0 && stSAR.den > 0) ? stSAR : AVRational(num: 1, den: 1)
    }
}
