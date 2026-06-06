// Anime4K-Upscaler/ViewModels/CoreMLUpscaler.swift
import CoreML
import AVFoundation
import VideoToolbox
import CoreImage

class CoreMLUpscaler {
    private let model: MLModel
    private let ciContext: CIContext

    init(modelName: String) throws {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw NSError(domain: "CoreMLUpscaler", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model \(modelName).mlmodelc not found in bundle."])
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine  // Explicit ANE routing
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: NSNull()
        ])
    }

    func upscaleFrame(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["input": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try model.prediction(from: input)
        guard let outputBuffer = output.featureValue(for: "output")?.imageBufferValue else {
            throw NSError(domain: "CoreMLUpscaler", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to extract output frame from CoreML."])
        }
        return outputBuffer
    }

    /// Tiled upscaling of a full-sized video frame.
    /// Splits the frame into static tile sizes, runs Core ML on each tile, and composites the result.
    func upscaleFullFrame(_ inputBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(inputBuffer)
        let height = CVPixelBufferGetHeight(inputBuffer)
        let inputImage = CIImage(cvPixelBuffer: inputBuffer)
        return try upscaleFullFrameImage(inputImage, width: width, height: height)
    }

    /// Tiled upscaling of a CIImage.
    /// Splits the image into static tile sizes, runs Core ML on each tile, and composites the result.
    func upscaleFullFrameImage(_ inputImage: CIImage, width: Int, height: Int) throws -> CVPixelBuffer {
        // Choose tile dimensions based on resolution
        // The models are converted with static EnumeratedShapes: 270x480, 135x240, 90x160
        let tileWidth: Int
        let tileHeight: Int
        
        if width >= 1920 {
            tileWidth = 480
            tileHeight = 270
        } else if width >= 1280 {
            tileWidth = 240
            tileHeight = 135
        } else {
            tileWidth = 160
            tileHeight = 90
        }
        
        let upscaleScale = 4
        let outputWidth = width * upscaleScale
        let outputHeight = height * upscaleScale
        
        guard let outputBuffer = createPixelBuffer(width: outputWidth, height: outputHeight, pixelFormat: kCVPixelFormatType_32BGRA) else {
            throw NSError(domain: "CoreMLUpscaler", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create output pixel buffer."])
        }
        
        var fullUpscaledImage: CIImage?
        
        // Allocate a reusable pixel buffer for the input tile
        guard let tileInputBuffer = createPixelBuffer(width: tileWidth, height: tileHeight, pixelFormat: kCVPixelFormatType_32BGRA) else {
            throw NSError(domain: "CoreMLUpscaler", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create tile input pixel buffer."])
        }
        
        var y = 0
        while y < height {
            let yOrigin = min(y, height - tileHeight)
            var x = 0
            while x < width {
                let xOrigin = min(x, width - tileWidth)
                
                // Crop the tile from input frame using CIImage
                let cropRect = CGRect(x: xOrigin, y: yOrigin, width: tileWidth, height: tileHeight)
                let croppedImage = inputImage.cropped(to: cropRect)
                
                // Render the cropped tile to our static-sized tile input buffer
                ciContext.render(croppedImage, to: tileInputBuffer, bounds: cropRect, colorSpace: nil)
                
                // Upscale the tile using Core ML
                let upscaledTileBuffer = try upscaleFrame(tileInputBuffer)
                let upscaledTileImage = CIImage(cvPixelBuffer: upscaledTileBuffer)
                
                // Position the upscaled tile in the output image coordinate space (scaled by 4x)
                let tx = CGFloat(xOrigin * upscaleScale)
                let ty = CGFloat(yOrigin * upscaleScale)
                let translatedTile = upscaledTileImage.transformed(by: CGAffineTransform(translationX: tx, y: ty))
                
                // Composite the tile over the accumulating output frame
                if let currentImage = fullUpscaledImage {
                    fullUpscaledImage = translatedTile.composited(over: currentImage)
                } else {
                    fullUpscaledImage = translatedTile
                }
                
                x += tileWidth
            }
            y += tileHeight
        }
        
        // Render the final composited image to the output buffer
        if let finalImage = fullUpscaledImage {
            ciContext.render(finalImage, to: outputBuffer, bounds: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight), colorSpace: nil)
        }
        
        return outputBuffer
    }

    private func createPixelBuffer(width: Int, height: Int, pixelFormat: OSType) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, attrs, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }
}
