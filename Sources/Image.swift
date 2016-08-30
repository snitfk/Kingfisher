//
//  Image.swift
//  Kingfisher
//
//  Created by Wei Wang on 16/1/6.
//
//  Copyright (c) 2016 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


#if os(macOS)
import AppKit
public typealias Image = NSImage
public typealias Color = NSColor

private var imagesKey: Void?
private var durationKey: Void?
#else
import UIKit
import MobileCoreServices
public typealias Image = UIImage
public typealias Color = UIColor
    
private var imageSourceKey: Void?
private var animatedImageDataKey: Void?
#endif

import ImageIO
import CoreGraphics

#if os(iOS) || os(macOS) || os(tvOS)
import Accelerate
import CoreImage
    
private let ciContext = CIContext(options: nil)
#endif

// MARK: - Image Properties
extension Image {
#if os(macOS)
    var cgImage: CGImage? {
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    var kf_scale: CGFloat {
        return 1.0
    }
    
    fileprivate(set) var kf_images: [Image]? {
        get {
            return objc_getAssociatedObject(self, &imagesKey) as? [Image]
        }
        set {
            objc_setAssociatedObject(self, &imagesKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate(set) var kf_duration: TimeInterval {
        get {
            return objc_getAssociatedObject(self, &durationKey) as? TimeInterval ?? 0.0
        }
        set {
            objc_setAssociatedObject(self, &durationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var kf_size: CGSize {
        return representations.reduce(CGSize.zero, { size, rep in
            return CGSize(width: max(size.width, CGFloat(rep.pixelsWide)), height: max(size.height, CGFloat(rep.pixelsHigh)))
        })
    }
    
#else
    var kf_scale: CGFloat {
        return scale
    }
    
    var kf_images: [Image]? {
        return images
    }
    
    var kf_duration: TimeInterval {
        return duration
    }
    
    fileprivate(set) var kf_imageSource: ImageSource? {
        get {
            return objc_getAssociatedObject(self, &imageSourceKey) as? ImageSource
        }
        set {
            objc_setAssociatedObject(self, &imageSourceKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
        
    fileprivate(set) var kf_animatedImageData: Data? {
        get {
            return objc_getAssociatedObject(self, &animatedImageDataKey) as? Data
        }
        set {
            objc_setAssociatedObject(self, &animatedImageDataKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var kf_size: CGSize {
        return size
    }
#endif
}

// MARK: - Image Conversion
extension Image {
#if os(macOS)
    static func kf_image(cgImage: CGImage, scale: CGFloat, refImage: Image?) -> Image {
        return Image(cgImage: cgImage, size: CGSize.zero)
    }
    
    /**
    Normalize the image. This method does nothing in OS X.
    
    - returns: The image itself.
    */
    public func kf_normalized() -> Image {
        return self
    }
    
    static func kf_animatedImage(images: [Image], duration: TimeInterval) -> Image? {
        return nil
    }
#else
    static func kf_image(cgImage: CGImage, scale: CGFloat, refImage: Image?) -> Image {
        if let refImage = refImage {
            return Image(cgImage: cgImage, scale: scale, orientation: refImage.imageOrientation)
        } else {
            return Image(cgImage: cgImage, scale: scale, orientation: .up)
        }
    }
    
    /**
     Normalize the image. This method will try to redraw an image with orientation and scale considered.
     
     - returns: The normalized image with orientation set to up and correct scale.
     */
    public func kf_normalized() -> Image {
        // prevent animated image (GIF) lose it's images
        if images != nil {
            return self
        }
    
        if imageOrientation == .up {
            return self
        }
    
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: CGPoint.zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    
        return normalizedImage!
    }
    
    static func kf_animated(with images: [Image], forDuration duration: TimeInterval) -> Image? {
        return Image.animatedImage(with: images, duration: duration)
    }
#endif
}

// MARK: - Image Representation
extension Image {
    // MARK: - PNG
    func pngRepresentation() -> Data? {
        #if os(macOS)
            if let cgimage = cgImage {
                let rep = NSBitmapImageRep(cgImage: cgimage)
                return rep.representation(using: .PNG, properties: [:])
            }
            return nil
        #else
            return UIImagePNGRepresentation(self)
        #endif
    }
    
    // MARK: - JPEG
    func jpegRepresentation(compressionQuality: CGFloat) -> Data? {
        #if os(macOS)
            guard let cgImage = cgImage else {
                return nil
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using:.JPEG, properties: [NSImageCompressionFactor: compressionQuality])
        #else
            return UIImageJPEGRepresentation(self, compressionQuality)
        #endif
    }
    
    // MARK: - GIF
    func gifRepresentation() -> Data? {
        #if os(macOS)
            return gifRepresentation(duration: 0.0, repeatCount: 0)
        #else
            return kf_animatedImageData
        #endif
    }
    
    func gifRepresentation(duration: TimeInterval, repeatCount: Int) -> Data? {
        guard let images = kf_images else {
            return nil
        }
        
        let frameCount = images.count
        let gifDuration = duration <= 0.0 ? kf_duration / Double(frameCount) : duration / Double(frameCount)
        
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: gifDuration]]
        let imageProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: repeatCount]]
        
        let data = NSMutableData()
        
        guard let destination = CGImageDestinationCreateWithData(data, kUTTypeGIF, frameCount, nil) else {
            return nil
        }
        CGImageDestinationSetProperties(destination, imageProperties as CFDictionary)
        
        for image in images {
            CGImageDestinationAddImage(destination, image.cgImage!, frameProperties as CFDictionary)
        }
        
        return CGImageDestinationFinalize(destination) ? data.copy() as? Data : nil
    }
}

// MARK: - Create images from data
extension Image {
    static func kf_animated(with data: Data, preloadAll: Bool) -> Image? {
        return kf_animated(with: data, scale: 1.0, duration: 0.0, preloadAll: preloadAll)
    }
    
    static func kf_animated(with data: Data, scale: CGFloat, duration: TimeInterval, preloadAll: Bool) -> Image? {
        
        func decode(from imageSource: CGImageSource, for options: NSDictionary) -> ([Image], TimeInterval)? {

            //Calculates frame duration for a gif frame out of the kCGImagePropertyGIFDictionary dictionary
            func frameDuration(from gifInfo: NSDictionary) -> Double {
                let gifDefaultFrameDuration = 0.100
                
                let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
                let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? NSNumber
                let duration = unclampedDelayTime ?? delayTime
                
                guard let frameDuration = duration else { return gifDefaultFrameDuration }
                
                return frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : gifDefaultFrameDuration
            }
            
            let frameCount = CGImageSourceGetCount(imageSource)
            var images = [Image]()
            var gifDuration = 0.0
            for i in 0 ..< frameCount {
                
                guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, i, options) else {
                    return nil
                }
                
                if frameCount == 1 {
                    // Single frame
                    gifDuration = Double.infinity
                } else {
                    // Animated GIF
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil),
                          let gifInfo = (properties as NSDictionary)[kCGImagePropertyGIFDictionary as String] as? NSDictionary else
                    {
                        return nil
                    }
                    gifDuration += frameDuration(from: gifInfo)
                }
                
                images.append(Image.kf_image(cgImage: imageRef, scale: scale, refImage: nil))
            }
            
            return (images, gifDuration)
        }
        
        // Start of kf_animatedImageWithGIFData
        let options: NSDictionary = [kCGImageSourceShouldCache as String: true, kCGImageSourceTypeIdentifierHint as String: kUTTypeGIF]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }
        
#if os(macOS)
        guard let (images, gifDuration) = decode(from: imageSource, for: options) else {
            return nil
        }
        let image = Image(data: data)
        image?.kf_images = images
        image?.kf_duration = gifDuration
    
        return image
#else
    
        if preloadAll {
            guard let (images, gifDuration) = decode(from: imageSource, for: options) else {
                return nil
            }
            let image = Image.kf_animated(with: images, forDuration: duration <= 0.0 ? gifDuration : duration)
            image?.kf_animatedImageData = data
            return image
        } else {
            let image = Image(data: data)
            image?.kf_animatedImageData = data
            image?.kf_imageSource = ImageSource(ref: imageSource)
            return image
        }
#endif
    }
    
    static func kf_image(data: Data, scale: CGFloat, preloadAllGIFData: Bool) -> Image? {
        var image: Image?
        #if os(macOS)
            switch data.kf_imageFormat {
            case .JPEG: image = Image(data: data)
            case .PNG: image = Image(data: data)
            case .GIF: image = Image.kf_animated(with: data, scale: scale, duration: 0.0, preloadAll: preloadAllGIFData)
            case .unknown: image = Image(data: data)
            }
        #else
            switch data.kf_imageFormat {
            case .JPEG: image = Image(data: data, scale: scale)
            case .PNG: image = Image(data: data, scale: scale)
            case .GIF: image = Image.kf_animated(with: data, scale: scale, duration: 0.0, preloadAll: preloadAllGIFData)
            case .unknown: image = Image(data: data, scale: scale)
            }
        #endif
        
        return image
    }
}

// MARK: - Image Transforming
extension Image {
    // MARK: - Round Corner
    func kf_image(withRoundRadius radius: CGFloat, fit size: CGSize, scale: CGFloat) -> Image? {
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        
        #if os(macOS)
            let output = NSImage(size: rect.size)
            output.lockFocus()
            
            NSGraphicsContext.current()?.imageInterpolation = .high
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            path.windingRule = .evenOddWindingRule
            path.addClip()
            draw(in: rect)
            output.unlockFocus()
        #else
            UIGraphicsBeginImageContextWithOptions(rect.size, false, scale)
            
            guard let context = UIGraphicsGetCurrentContext() else {
                return nil
            }
            
            let path = UIBezierPath(roundedRect: rect, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: radius, height: radius)).cgPath
            context.addPath(path)
            context.clip()
            
            draw(in: rect)
            
            let output = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

        #endif
        
        return output
    }
    
    #if os(iOS) || os(tvOS)
    func kf_resize(to size: CGSize, for contentMode: UIViewContentMode) -> Image {
        switch contentMode {
        case .scaleAspectFit:
            let newSize = self.size.kf_constrained(size)
            return kf_resize(to: newSize)
        case .scaleAspectFill:
            let newSize = self.size.kf_filling(size)
            return kf_resize(to: newSize)
        default:
            return kf_resize(to: size)
        }
    }
    #endif
    
    // MARK: - Resize
    func kf_resize(to size: CGSize) -> Image {
        
        guard let cgImage = cgImage?.fixed else {
            assertionFailure("[Kingfisher] Resizing only works for CG-based image.")
            return self
        }
        
        guard kf_size.width >= size.width && kf_size.height >= size.height && size.width > 0 && size.height > 0 else {
            print("[Kingfisher] Invalid resizing target size: \(size). The size should be smaller than original size and larger than 0")
            return self
        }
        
        let bitsPerComponent = cgImage.bitsPerComponent
        let bytesPerRow = cgImage.bytesPerRow
        let colorSpace = cgImage.colorSpace
        let bitmapInfo = cgImage.bitmapInfo.fixed

        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace!,
                                      bitmapInfo: bitmapInfo.rawValue) else
        {
            assertionFailure("[Kingfisher] Failed to create CG context for resizing image.")
            return self
        }
        
        context.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: size))
        
        #if os(macOS)
            let result = context.makeImage().flatMap { Image(cgImage: $0, size: size) }
        #else
            let result = context.makeImage().flatMap { Image(cgImage: $0) }
        #endif
        guard let scaledImage = result else {
            assertionFailure("[Kingfisher] Can not make an resized image within context.")
            return self
        }
        
        return scaledImage
    }
    
    // MARK: - Blur
    func kf_blurred(withRadius radius: CGFloat) -> Image {
        #if os(watchOS)
            return self
        #else
            guard let cgImage = cgImage?.fixed else {
                assertionFailure("[Kingfisher] Blur only works for CG-based image.")
                return self
            }
            
            // http://www.w3.org/TR/SVG/filters.html#feGaussianBlurElement
            // let d = floor(s * 3*sqrt(2*pi)/4 + 0.5)
            // if d is odd, use three box-blurs of size 'd', centered on the output pixel.
            let s = max(radius, 2.0)
            // We will do blur on a resized image (*0.5), so the blur radius could be half as well.
            var targetRadius = floor((Double(s * 3.0) * sqrt(2 * M_PI) / 4.0 + 0.5))
            
            if targetRadius.isEven {
                targetRadius += 1
            }
            
            let iterations: Int
            if radius < 0.5 {
                iterations = 1
            } else if radius < 1.5 {
                iterations = 2
            } else {
                iterations = 3
            }
            
            let w = Int(kf_size.width)
            let h = Int(kf_size.height)
            let rowBytes = Int(CGFloat(cgImage.bytesPerRow))
            
            let inDataPointer = malloc(rowBytes * Int(h))
            defer {
                free(inDataPointer)
            }
            
            let bitmapInfo = cgImage.bitmapInfo.fixed
            guard let context = CGContext(data: inDataPointer,
                                          width: w,
                                          height: h,
                                          bitsPerComponent: cgImage.bitsPerComponent,
                                          bytesPerRow: rowBytes,
                                          space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: bitmapInfo.rawValue) else
            {
                assertionFailure("[Kingfisher] Failed to create CG context for blurring image.")
                return self
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            
            
            var inBuffer = vImage_Buffer(data: inDataPointer, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
            
            let outDataPointer = malloc(rowBytes * Int(h))
            defer {
                free(outDataPointer)
            }
            
            var outBuffer = vImage_Buffer(data: outDataPointer, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
            
            for _ in 0 ..< iterations {
                vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, nil, 0, 0, UInt32(targetRadius), UInt32(targetRadius), nil, vImage_Flags(kvImageEdgeExtend))
                (inBuffer, outBuffer) = (outBuffer, inBuffer)
            }
            
            guard let outContext = CGContext(data: inDataPointer,
                                             width: w,
                                             height: h,
                                             bitsPerComponent: cgImage.bitsPerComponent,
                                             bytesPerRow: rowBytes,
                                             space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: cgImage.bitmapInfo.rawValue) else
            {
                assertionFailure("[Kingfisher] Failed to create CG context for blurring image.")
                return self
            }
            
            #if os(macOS)
                let result = outContext.makeImage().flatMap { Image(cgImage: $0, size: kf_size) }
            #else
                let result = outContext.makeImage().flatMap { Image(cgImage: $0) }
            #endif
            guard let blurredImage = result else {
                assertionFailure("[Kingfisher] Can not make an resized image within context.")
                return self
            }
            
            return blurredImage
        #endif
    }
    
    // MARK: - Overlay
    func kf_overlaying(with color: Color, fraction: CGFloat) -> Image {

        let rect = CGRect(x: 0, y: 0, width: kf_size.width, height: kf_size.height)
        
        #if os(macOS)
            let output = NSImage(size: rect.size)
            output.lockFocus()
            
            NSGraphicsContext.current()?.imageInterpolation = .high
            draw(in: rect)
            color.withAlphaComponent(1 - fraction).set()
            NSRectFillUsingOperation(rect, .sourceAtop)
            
            output.unlockFocus()
            
            return output
        #else
            UIGraphicsBeginImageContextWithOptions(size, false, scale)

            color.set()
            UIRectFill(rect)
            draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
            
            if fraction > 0 {
                draw(in: rect, blendMode: .sourceAtop, alpha: fraction)
            }
            
            let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return tintedImage ?? self
        #endif
    }
    
    // MARK: - Tint
    func kf_tinted(with color: Color) -> Image {
        #if os(watchOS)
            return self
        #else
        guard let cgImage = cgImage else {
            assertionFailure("[Kingfisher] Tint image only works for CG-based image.")
            return self
        }
    
            
        let colorFilter = CIFilter(name: "CIConstantColorGenerator")!
        colorFilter.setValue(CIColor(color: color), forKey: kCIInputColorKey)
        
        let colorImage = colorFilter.outputImage
            
        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CISourceOverCompositing")!
        filter.setValue(colorImage, forKey: kCIInputImageKey)
        filter.setValue(input, forKey: kCIInputBackgroundImageKey)
        
        guard let output = filter.outputImage?.cropping(to: input.extent) else {
            assertionFailure("[Kingfisher] Tint filter failed to create output image.")
            return self
        }
            
        guard let result = ciContext.createCGImage(output, from: output.extent) else {
            assertionFailure("[Kingfisher] Can not make an tint image within context.")
            return self
        }
            
        #if os(macOS)
            return Image(cgImage: result, size: .zero)
        #else
            return Image(cgImage: result)
        #endif
        #endif
    }
    
    // MARK: - Color Control
    func kf_adjusted(brightness: CGFloat, contrast: CGFloat, saturation: CGFloat, inputEV: CGFloat) -> Image {
        #if os(watchOS)
        return self
        #else
        guard let cgImage = cgImage else {
            assertionFailure("[Kingfisher] B&W only works for CG-based image.")
            return self
        }
        let input = CIImage(cgImage: cgImage)
        
        let paramsColor = [kCIInputBrightnessKey: brightness,
                             kCIInputContrastKey: contrast,
                           kCIInputSaturationKey: saturation]
            
        let blackAndWhite = input.applyingFilter("CIColorControls", withInputParameters: paramsColor)
        let paramsExposure = [kCIInputEVKey: inputEV]
        let output = blackAndWhite.applyingFilter("CIExposureAdjust", withInputParameters: paramsExposure)
        
        guard let result = ciContext.createCGImage(output, from: output.extent) else {
            assertionFailure("Can not make an B&W image within context.")
            return self
        }
            
        #if os(macOS)
        return Image(cgImage: result, size: .zero)
        #else
        return Image(cgImage: result)
        #endif
        #endif
    }
}

// MARK: - Decode
extension Image {
    func kf_decoded() -> Image? {
        return self.kf_decoded(scale: kf_scale)
    }
    
    func kf_decoded(scale: CGFloat) -> Image? {
        // prevent animated image (GIF) lose it's images
#if os(iOS)
        if kf_imageSource != nil {
            return self
        }
#else
        if kf_images != nil {
            return self
        }
#endif
        
        guard let imageRef = self.cgImage else {
            assertionFailure("[Kingfisher] Decoding only works for CG-based image.")
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = imageRef.bitmapInfo.fixed
        
        let context = CGContext(data: nil, width: imageRef.width, height: imageRef.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        if let context = context {
            let rect = CGRect(x: 0, y: 0, width: imageRef.width, height: imageRef.height)
            context.draw(imageRef, in: rect)
            let decompressedImageRef = context.makeImage()
            return Image.kf_image(cgImage: decompressedImageRef!, scale: scale, refImage: self)
        } else {
            return nil
        }
    }
}

/// Reference the source image reference
class ImageSource {
    var imageRef: CGImageSource?
    init(ref: CGImageSource) {
        self.imageRef = ref
    }
}

// MARK: - Image format
private struct ImageHeaderData {
    static var PNG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static var JPEG_SOI: [UInt8] = [0xFF, 0xD8]
    static var JPEG_IF: [UInt8] = [0xFF]
    static var GIF: [UInt8] = [0x47, 0x49, 0x46]
}

enum ImageFormat {
    case unknown, PNG, JPEG, GIF
}


// MARK: - Misc Helpers
extension Data {
    var kf_imageFormat: ImageFormat {
        var buffer = [UInt8](repeating: 0, count: 8)
        (self as NSData).getBytes(&buffer, length: 8)
        if buffer == ImageHeaderData.PNG {
            return .PNG
        } else if buffer[0] == ImageHeaderData.JPEG_SOI[0] &&
            buffer[1] == ImageHeaderData.JPEG_SOI[1] &&
            buffer[2] == ImageHeaderData.JPEG_IF[0]
        {
            return .JPEG
        } else if buffer[0] == ImageHeaderData.GIF[0] &&
            buffer[1] == ImageHeaderData.GIF[1] &&
            buffer[2] == ImageHeaderData.GIF[2]
        {
            return .GIF
        }
        
        return .unknown
    }
}

extension CGSize {
    func kf_constrained(_ size: CGSize) -> CGSize {
        let aspectWidth = round(kf_aspectRatio * size.height)
        let aspectHeight = round(size.width / kf_aspectRatio)
        
        return aspectWidth > size.width ? CGSize(width: size.width, height: aspectHeight) : CGSize(width: aspectWidth, height: size.height)
    }
    
    func kf_filling(_ size: CGSize) -> CGSize {
        let aspectWidth = round(kf_aspectRatio * size.height)
        let aspectHeight = round(size.width / kf_aspectRatio)
        
        return aspectWidth < size.width ? CGSize(width: size.width, height: aspectHeight) : CGSize(width: aspectWidth, height: size.height)
    }
    
    private var kf_aspectRatio: CGFloat {
        return height == 0.0 ? 1.0 : width / height
    }
}

extension CGImage {
    var isARGB8888: Bool {
        return bitsPerPixel == 32 && bitsPerComponent == 8 && bitmapInfo.contains(.alphaInfoMask)
    }
    
    var fixed: CGImage {
        if isARGB8888 { return self }

        // Convert to ARGB if it isn't
        guard let context = CGContext.createARGBContext(from: self) else {
            assertionFailure("[Kingfisher] Failed to create CG context when converting non ARGB image.")
            return self
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let r = context.makeImage() else {
            assertionFailure("[Kingfisher] Failed to create CG image when converting non ARGB image.")
            return self
        }
        return r
    }
}

extension CGBitmapInfo {
    var fixed: CGBitmapInfo {
        var fixed = self
        let alpha = (rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        if alpha == CGImageAlphaInfo.none.rawValue {
            fixed.remove(.alphaInfoMask)
            fixed = CGBitmapInfo(rawValue: fixed.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        } else if !(alpha == CGImageAlphaInfo.noneSkipFirst.rawValue) || !(alpha == CGImageAlphaInfo.noneSkipLast.rawValue) {
            fixed.remove(.alphaInfoMask)
            fixed = CGBitmapInfo(rawValue: fixed.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        }
        return fixed
    }
}

extension CGContext {
    static func createARGBContext(from imageRef: CGImage) -> CGContext? {
        
        let w = imageRef.width
        let h = imageRef.height
        let bytesPerRow = w * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let data = malloc(bytesPerRow * h)
        defer {
            free(data)
        }
        
        let bitmapInfo = imageRef.bitmapInfo.fixed
        
        // Create the bitmap context. We want pre-multiplied ARGB, 8-bits
        // per component. Regardless of what the source image format is
        // (CMYK, Grayscale, and so on) it will be converted over to the format
        // specified here.
        return CGContext(data: data,
                         width: w,
                         height: h,
                         bitsPerComponent: imageRef.bitsPerComponent,
                         bytesPerRow: bytesPerRow,
                         space: colorSpace,
                         bitmapInfo: bitmapInfo.rawValue)
    }
}

extension Double {
    var isEven: Bool {
        return truncatingRemainder(dividingBy: 2.0) == 0
    }
}


