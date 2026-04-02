import Foundation
import Metal
import MetalPerformanceShaders

private enum A4KMPSWeightLayout {
	case columnMajor
	case rowMajor

	static func fromEnvironment(_ env: [String: String]) -> A4KMPSWeightLayout {
		let raw = env["A4K_MPS_WEIGHT_LAYOUT"]?.lowercased()
		if raw == "row" || raw == "row-major" {
			return .rowMajor
		}
		return .columnMajor
	}
}

private enum A4KMPSWeightPackOrder {
	case ohwi
	case oihw

	static func fromEnvironment(_ env: [String: String]) -> A4KMPSWeightPackOrder {
		switch env["A4K_MPS_WEIGHT_PACK"]?.lowercased() {
		case "oihw":
			return .oihw
		default:
			return .ohwi
		}
	}
}

private struct A4KMPSPlannerConfig {
	let enabled: Bool
	let validateEquivalence: Bool
	let validationSampleSize: Int
	let equivalenceMaxAbs: Float
	let equivalenceMeanAbs: Float
	let maxPlans: Int?
	let includePasses: Set<Int>?
	let weightLayout: A4KMPSWeightLayout
	let weightPackOrder: A4KMPSWeightPackOrder
	let flipKernelX: Bool
	let flipKernelY: Bool
	let offsetX: Int
	let offsetY: Int

	static func fromEnvironment() -> A4KMPSPlannerConfig {
		let env = ProcessInfo.processInfo.environment
		let enabled = env["A4K_ENABLE_MPS_CONV"] == "1"
		let validateEquivalence = (env["A4K_MPS_VALIDATE_EQUIVALENCE"] ?? "1") != "0"
		let sampleSize = max(8, min(128, Int(env["A4K_MPS_EQ_SAMPLE_SIZE"] ?? "64") ?? 64))
		let maxAbs = Float(env["A4K_MPS_EQ_MAX_ABS"] ?? "0.003") ?? 0.003
		let meanAbs = Float(env["A4K_MPS_EQ_MEAN_ABS"] ?? "0.0005") ?? 0.0005
		let maxPlans = env["A4K_MPS_MAX_PLANS"].flatMap(Int.init)
		let includePasses = parsePassList(env["A4K_MPS_INCLUDE_PASSES"])
		let weightLayout = A4KMPSWeightLayout.fromEnvironment(env)
		let weightPackOrder = A4KMPSWeightPackOrder.fromEnvironment(env)
		let flipKernelX = (env["A4K_MPS_FLIP_KERNEL_X"] ?? "0") == "1"
		let flipKernelY = (env["A4K_MPS_FLIP_KERNEL_Y"] ?? "0") == "1"
		let offsetX = max(0, min(2, Int(env["A4K_MPS_OFFSET_X"] ?? "1") ?? 1))
		let offsetY = max(0, min(2, Int(env["A4K_MPS_OFFSET_Y"] ?? "1") ?? 1))

		return A4KMPSPlannerConfig(
			enabled: enabled,
			validateEquivalence: validateEquivalence,
			validationSampleSize: sampleSize,
			equivalenceMaxAbs: maxAbs,
			equivalenceMeanAbs: meanAbs,
			maxPlans: maxPlans,
			includePasses: includePasses,
			weightLayout: weightLayout,
			weightPackOrder: weightPackOrder,
			flipKernelX: flipKernelX,
			flipKernelY: flipKernelY,
			offsetX: offsetX,
			offsetY: offsetY
		)
	}

	private static func parsePassList(_ raw: String?) -> Set<Int>? {
		guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return nil
		}

		let values = raw
			.split(separator: ",")
			.compactMap { token in
				Int(token.trimmingCharacters(in: .whitespacesAndNewlines))
			}

		return values.isEmpty ? nil : Set(values)
	}
}

private struct A4KValidatedMPSWeights {
	let packedWeights: [Float]
	let bias: [Float]
}

final class A4KMPSConvolutionDataSource: NSObject, MPSCNNConvolutionDataSource {
	private let descriptorValue: MPSCNNConvolutionDescriptor
	private let labelValue: String
	private let weightsPointer: UnsafeMutablePointer<Float>
	private let weightsCount: Int
	private let biasPointer: UnsafeMutablePointer<Float>

	init(label: String,
		 kernelWidth: Int,
		 kernelHeight: Int,
		 inputFeatureChannels: Int,
		 outputFeatureChannels: Int,
		 weights: [Float],
		 bias: [Float]) {
		self.labelValue = label
		self.weightsCount = weights.count
		self.descriptorValue = MPSCNNConvolutionDescriptor(
			kernelWidth: kernelWidth,
			kernelHeight: kernelHeight,
			inputFeatureChannels: inputFeatureChannels,
			outputFeatureChannels: outputFeatureChannels,
			neuronFilter: nil
		)

		self.weightsPointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, weights.count))
		if weights.isEmpty {
			self.weightsPointer.pointee = 0
		} else {
			self.weightsPointer.initialize(from: weights, count: weights.count)
		}

		var normalizedBias = bias
		if normalizedBias.count < outputFeatureChannels {
			normalizedBias.append(contentsOf: repeatElement(0, count: outputFeatureChannels - normalizedBias.count))
		}
		if normalizedBias.count > outputFeatureChannels {
			normalizedBias = Array(normalizedBias.prefix(outputFeatureChannels))
		}

		self.biasPointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, outputFeatureChannels))
		if normalizedBias.isEmpty {
			self.biasPointer.pointee = 0
		} else {
			self.biasPointer.initialize(from: normalizedBias, count: normalizedBias.count)
		}
	}

	deinit {
		if weightsCount > 0 {
			weightsPointer.deinitialize(count: weightsCount)
		}
		weightsPointer.deallocate()

		let biasChannels = max(1, descriptorValue.outputFeatureChannels)
		biasPointer.deinitialize(count: biasChannels)
		biasPointer.deallocate()
	}

	func dataType() -> MPSDataType {
		.float32
	}

	func descriptor() -> MPSCNNConvolutionDescriptor {
		descriptorValue
	}

	func weights() -> UnsafeMutableRawPointer {
		UnsafeMutableRawPointer(weightsPointer)
	}

	func biasTerms() -> UnsafeMutablePointer<Float>? {
		biasPointer
	}

	func load() -> Bool {
		true
	}

	func purge() {
		// Keep weights pinned for the lifetime of the pipeline.
	}

	func label() -> String? {
		labelValue
	}

	func copy(with zone: NSZone? = nil) -> Any {
		self
	}
}

struct A4KMPSPassPlan {
	fileprivate let dataSource: A4KMPSConvolutionDataSource
	fileprivate let convolution: MPSCNNConvolution

	func encode(commandBuffer: MTLCommandBuffer,
				sourceTexture: MTLTexture,
				destinationTexture: MTLTexture) -> Bool {
		guard sourceTexture.width == destinationTexture.width,
			  sourceTexture.height == destinationTexture.height,
			  sourceTexture.pixelFormat == .rgba16Float,
			  destinationTexture.pixelFormat == .rgba16Float else {
			return false
		}

		let sourceImage = MPSImage(texture: sourceTexture, featureChannels: 4)
		let destinationImage = MPSImage(texture: destinationTexture, featureChannels: 4)
		convolution.encode(commandBuffer: commandBuffer,
					   sourceImage: sourceImage,
					   destinationImage: destinationImage)
		return true
	}
}

struct A4KMPSPassMetadata {
	let passIndex: Int
	let functionName: String
	let inputTextureNames: [String]
}

enum A4KMPSConvolutionPlanner {
	private static let matrixRegex = try! NSRegularExpression(
		pattern: "mat4\\(([^\\)]*)\\)\\s*\\*\\s*go_0\\(\\s*([+-]?(?:\\d*\\.?\\d+(?:[eE][+-]?\\d+)?))\\s*,\\s*([+-]?(?:\\d*\\.?\\d+(?:[eE][+-]?\\d+)?))\\s*\\)",
		options: []
	)

	private static let biasRegex = try! NSRegularExpression(
		pattern: "result\\s*\\+=\\s*vec4\\(([^\\)]*)\\)\\s*;",
		options: []
	)

	static func buildPlans(device: MTLDevice,
					   library: MTLLibrary,
					   shaderFileName: String,
					   passMetadata: [A4KMPSPassMetadata],
					   metalSource: String) -> [Int: A4KMPSPassPlan] {
		let config = A4KMPSPlannerConfig.fromEnvironment()
		guard config.enabled else {
			return [:]
		}

		guard MPSSupportsMTLDevice(device) else {
			NSLog("[Anime4KMPS] Device does not support MPS CNN (%@)", shaderFileName)
			return [:]
		}

		var plans: [Int: A4KMPSPassPlan] = [:]

		for metadata in passMetadata {
			if let include = config.includePasses,
			   !include.contains(metadata.passIndex) {
				continue
			}

			if let maxPlans = config.maxPlans,
			   plans.count >= maxPlans {
				break
			}

			guard metadata.inputTextureNames.count == 1 else {
				continue
			}

			let functionName = metadata.functionName
			guard let section = sectionForFunction(functionName: functionName, in: metalSource) else {
				continue
			}

			if section.contains("go_1(") || section.contains("go_2(") || section.contains("go_3(") {
				continue
			}

			guard let parsed = parseSingleInput3x3Pass(
				section: section,
				weightLayout: config.weightLayout,
				weightPackOrder: config.weightPackOrder,
				flipKernelX: config.flipKernelX,
				flipKernelY: config.flipKernelY
			) else {
				continue
			}

			let label = "A4K_MPS_\(shaderFileName)_\(functionName)"
			let dataSource = A4KMPSConvolutionDataSource(
				label: label,
				kernelWidth: 3,
				kernelHeight: 3,
				inputFeatureChannels: 4,
				outputFeatureChannels: 4,
				weights: parsed.packedWeights,
				bias: parsed.bias
			)

			let convolution = MPSCNNConvolution(device: device, weights: dataSource)
			convolution.edgeMode = .clamp
			convolution.offset = MPSOffset(x: config.offsetX, y: config.offsetY, z: 0)

			let plan = A4KMPSPassPlan(dataSource: dataSource, convolution: convolution)

			if config.validateEquivalence {
				let validation = validatePlanEquivalence(
					device: device,
					library: library,
					functionName: functionName,
					plan: plan,
					sampleSize: config.validationSampleSize,
					maxAbsThreshold: config.equivalenceMaxAbs,
					meanAbsThreshold: config.equivalenceMeanAbs
				)

				if !validation.accepted {
					NSLog("[Anime4KMPS] Skipping %@ pass %d (%@): equivalence failed (maxAbs=%.6f meanAbs=%.6f)",
						  shaderFileName,
						  metadata.passIndex,
						  functionName,
						  validation.maxAbs,
						  validation.meanAbs)
					continue
				}
			}

			plans[metadata.passIndex] = plan
		}

		if plans.isEmpty {
			NSLog("[Anime4KMPS] Enabled, but no parity-safe single-input 3x3 passes found for %@", shaderFileName)
		} else {
			NSLog("[Anime4KMPS] Built %d parity-safe pass plan(s) for %@", plans.count, shaderFileName)
		}

		return plans
	}

	private static func sectionForFunction(functionName: String,
								   in source: String) -> String? {
		guard let functionMarker = source.range(of: "// Function: \(functionName)") else {
			return nil
		}

		let tail = source[functionMarker.lowerBound...]
		if let nextShader = tail.dropFirst().range(of: "\n// Shader:") {
			return String(tail[..<nextShader.lowerBound])
		}
		return String(tail)
	}

	private static func parseSingleInput3x3Pass(section: String,
									weightLayout: A4KMPSWeightLayout,
									weightPackOrder: A4KMPSWeightPackOrder,
									flipKernelX: Bool,
									flipKernelY: Bool) -> A4KValidatedMPSWeights? {
		let range = NSRange(location: 0, length: (section as NSString).length)
		let matrixMatches = matrixRegex.matches(in: section, options: [], range: range)
		if matrixMatches.count != 9 {
			return nil
		}

		var kernels: [String: [Float]] = [:]

		for match in matrixMatches {
			guard match.numberOfRanges == 4,
				  let matrixRange = Range(match.range(at: 1), in: section),
				  let xRange = Range(match.range(at: 2), in: section),
				  let yRange = Range(match.range(at: 3), in: section) else {
				return nil
			}

			let matrixValues = parseFloatList(String(section[matrixRange]))
			if matrixValues.count != 16 {
				return nil
			}

			guard let xFloat = Float(String(section[xRange])),
				  let yFloat = Float(String(section[yRange])) else {
				return nil
			}

			let xRounded = Int(xFloat.rounded())
			let yRounded = Int(yFloat.rounded())
			guard abs(xFloat - Float(xRounded)) < 0.001,
				  abs(yFloat - Float(yRounded)) < 0.001,
				  (-1...1).contains(xRounded),
				  (-1...1).contains(yRounded) else {
				return nil
			}

			kernels["\(xRounded),\(yRounded)"] = matrixValues
		}

		for y in -1...1 {
			for x in -1...1 {
				if kernels["\(x),\(y)"] == nil {
					return nil
				}
			}
		}

		var bias = [Float](repeating: 0, count: 4)
		let biasMatches = biasRegex.matches(in: section, options: [], range: range)
		if let lastBias = biasMatches.last,
		   lastBias.numberOfRanges >= 2,
		   let biasRange = Range(lastBias.range(at: 1), in: section) {
			let parsedBias = parseFloatList(String(section[biasRange]))
			if parsedBias.count == 4 {
				bias = parsedBias
			}
		}

		var packedWeights = [Float](repeating: 0, count: 4 * 3 * 3 * 4)

		for outChannel in 0..<4 {
			for y in 0..<3 {
				for x in 0..<3 {
					let sourceX = flipKernelX ? (2 - x) : x
					let sourceY = flipKernelY ? (2 - y) : y
					let key = "\(sourceX - 1),\(sourceY - 1)"
					guard let matrix = kernels[key] else {
						return nil
					}

					for inChannel in 0..<4 {
						let matrixValue: Float
						switch weightLayout {
						case .columnMajor:
							matrixValue = matrix[inChannel * 4 + outChannel]
						case .rowMajor:
							matrixValue = matrix[outChannel * 4 + inChannel]
						}

						let packedIndex: Int
						switch weightPackOrder {
						case .ohwi:
							packedIndex = (((outChannel * 3 + y) * 3 + x) * 4 + inChannel)
						case .oihw:
							packedIndex = (((outChannel * 4 + inChannel) * 3 + y) * 3 + x)
						}

						packedWeights[packedIndex] = matrixValue
					}
				}
			}
		}

		return A4KValidatedMPSWeights(packedWeights: packedWeights, bias: bias)
	}

	private static func parseFloatList(_ raw: String) -> [Float] {
		raw
			.split(separator: ",")
			.compactMap { token in
				Float(token.trimmingCharacters(in: .whitespacesAndNewlines))
			}
	}

	private static func validatePlanEquivalence(device: MTLDevice,
									 library: MTLLibrary,
									 functionName: String,
									 plan: A4KMPSPassPlan,
									 sampleSize: Int,
									 maxAbsThreshold: Float,
									 meanAbsThreshold: Float) -> (accepted: Bool, maxAbs: Float, meanAbs: Float) {
		guard let function = library.makeFunction(name: functionName),
			  let pipeline = try? device.makeComputePipelineState(function: function),
			  let inputTexture = makeSharedRGBA16Texture(device: device, width: sampleSize, height: sampleSize),
			  let referenceTexture = makeSharedRGBA16Texture(device: device, width: sampleSize, height: sampleSize),
			  let mpsTexture = makeSharedRGBA16Texture(device: device, width: sampleSize, height: sampleSize),
			  let commandQueue = device.makeCommandQueue() else {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
		}

		var generator = A4KLCG(seed: 0xA4C54AFE)
		let pixelCount = sampleSize * sampleSize * 4
		var inputHalf = [UInt16](repeating: 0, count: pixelCount)
		for i in 0..<pixelCount {
			let value = generator.nextSignedUnit()
			inputHalf[i] = Float16(value).bitPattern
		}

		let bytesPerRow = sampleSize * 4 * MemoryLayout<UInt16>.size
		inputHalf.withUnsafeBytes { raw in
			guard let base = raw.baseAddress else { return }
			inputTexture.replace(region: MTLRegionMake2D(0, 0, sampleSize, sampleSize),
						mipmapLevel: 0,
						withBytes: base,
						bytesPerRow: bytesPerRow)
		}

		guard let sampler = makeClampNearestSampler(device: device) else {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
		}

		guard let referenceCB = commandQueue.makeCommandBuffer(),
			  let referenceEncoder = referenceCB.makeComputeCommandEncoder() else {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
		}

		referenceEncoder.setComputePipelineState(pipeline)
		referenceEncoder.setSamplerState(sampler, index: 0)
		referenceEncoder.setTexture(inputTexture, index: 0)
		referenceEncoder.setTexture(referenceTexture, index: 1)

		let threadgroup = recommendedThreadgroupSize(for: pipeline)
		let grid = MTLSize(width: sampleSize, height: sampleSize, depth: 1)
		referenceEncoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
		referenceEncoder.endEncoding()

		referenceCB.commit()
		referenceCB.waitUntilCompleted()
		if referenceCB.status == .error {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
		}

		guard let mpsCB = commandQueue.makeCommandBuffer() else {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
		}

		guard plan.encode(commandBuffer: mpsCB, sourceTexture: inputTexture, destinationTexture: mpsTexture) else {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
		}

		mpsCB.commit()
		mpsCB.waitUntilCompleted()
		if mpsCB.status == .error {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
		}

		var referenceHalf = [UInt16](repeating: 0, count: pixelCount)
		var mpsHalf = [UInt16](repeating: 0, count: pixelCount)

		referenceTexture.getBytes(&referenceHalf,
						 bytesPerRow: bytesPerRow,
						 from: MTLRegionMake2D(0, 0, sampleSize, sampleSize),
						 mipmapLevel: 0)
		mpsTexture.getBytes(&mpsHalf,
					 bytesPerRow: bytesPerRow,
					 from: MTLRegionMake2D(0, 0, sampleSize, sampleSize),
					 mipmapLevel: 0)

		var maxAbs: Float = 0
		var sumAbs: Float = 0

		for i in 0..<pixelCount {
			let ref = Float(Float16(bitPattern: referenceHalf[i]))
			let test = Float(Float16(bitPattern: mpsHalf[i]))
			let diff = abs(ref - test)
			maxAbs = max(maxAbs, diff)
			sumAbs += diff
		}

		let meanAbs = sumAbs / Float(max(1, pixelCount))
		let accepted = (maxAbs <= maxAbsThreshold) && (meanAbs <= meanAbsThreshold)
		return (accepted, maxAbs, meanAbs)
	}

	private static func makeSharedRGBA16Texture(device: MTLDevice,
									 width: Int,
									 height: Int) -> MTLTexture? {
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: .rgba16Float,
			width: max(1, width),
			height: max(1, height),
			mipmapped: false
		)
		descriptor.usage = [.shaderRead, .shaderWrite]
		descriptor.storageMode = .shared
		return device.makeTexture(descriptor: descriptor)
	}

	private static func makeClampNearestSampler(device: MTLDevice) -> MTLSamplerState? {
		let desc = MTLSamplerDescriptor()
		desc.minFilter = .nearest
		desc.magFilter = .nearest
		desc.sAddressMode = .clampToEdge
		desc.tAddressMode = .clampToEdge
		return device.makeSamplerState(descriptor: desc)
	}

	private static func recommendedThreadgroupSize(for pipeline: MTLComputePipelineState) -> MTLSize {
		let width = max(1, pipeline.threadExecutionWidth)
		let height = max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / width))
		return MTLSize(width: width, height: height, depth: 1)
	}
}

private struct A4KLCG {
	private var state: UInt64

	init(seed: UInt64) {
		self.state = seed
	}

	mutating func nextUInt32() -> UInt32 {
		state = state &* 6364136223846793005 &+ 1
		return UInt32(truncatingIfNeeded: state >> 16)
	}

	mutating func nextSignedUnit() -> Float {
		let raw = nextUInt32()
		let normalized = Float(raw) / Float(UInt32.max)
		return (normalized * 2.0) - 1.0
	}
}