import Foundation
import Metal
import MetalPerformanceShaders

private enum A4KMPSWeightLayout: CaseIterable {
	case columnMajor
	case rowMajor

	func cacheTag() -> String {
		switch self {
		case .columnMajor:
			return "column"
		case .rowMajor:
			return "row"
		}
	}

	static func fromEnvironment(_ env: [String: String]) -> A4KMPSWeightLayout {
		let raw = env["A4K_MPS_WEIGHT_LAYOUT"]?.lowercased()
		if raw == "row" || raw == "row-major" {
			return .rowMajor
		}
		return .columnMajor
	}
}

private struct A4KMPSChannelOrder {
	private let mapping: [Int]

	private init(mapping: [Int]) {
		self.mapping = mapping
	}

	static let rgba = A4KMPSChannelOrder(mapping: [0, 1, 2, 3])
	static let bgra = A4KMPSChannelOrder(mapping: [2, 1, 0, 3])
	static let argb = A4KMPSChannelOrder(mapping: [1, 2, 3, 0])
	static let abgr = A4KMPSChannelOrder(mapping: [3, 2, 1, 0])

	static func fromEnvironment(_ env: [String: String]) -> A4KMPSChannelOrder {
		fromToken(env["A4K_MPS_CHANNEL_ORDER"]) ?? .rgba
	}

	static func fromToken(_ raw: String?) -> A4KMPSChannelOrder? {
		switch raw?.lowercased() {
		case "rgba":
			return .rgba
		case "bgra":
			return .bgra
		case "argb":
			return .argb
		case "abgr":
			return .abgr
		default:
			return nil
		}
	}

	static func allPermutations() -> [A4KMPSChannelOrder] {
		var results: [A4KMPSChannelOrder] = []
		let seed = [0, 1, 2, 3]

		func permute(_ prefix: [Int], _ remaining: [Int]) {
			if remaining.isEmpty {
				results.append(A4KMPSChannelOrder(mapping: prefix))
				return
			}

			for index in remaining.indices {
				var nextPrefix = prefix
				nextPrefix.append(remaining[index])
				var nextRemaining = remaining
				nextRemaining.remove(at: index)
				permute(nextPrefix, nextRemaining)
			}
		}

		permute([], seed)
		return results
	}

	func map(_ logicalChannel: Int) -> Int {
		let safe = max(0, min(3, logicalChannel))
		return mapping[safe]
	}

	func inverse() -> A4KMPSChannelOrder {
		var inverted = [Int](repeating: 0, count: 4)
		for logical in 0..<4 {
			let mapped = map(logical)
			inverted[mapped] = logical
		}
		return A4KMPSChannelOrder(mapping: inverted)
	}

	func cacheTag() -> String {
		mapping.map(String.init).joined(separator: "")
	}
}

private struct A4KMPSWeightPackOrder {
	private let axes: [Character]

	private init(axes: [Character]) {
		self.axes = axes
	}

	static let ohwi = A4KMPSWeightPackOrder(axes: ["o", "h", "w", "i"])
	static let oihw = A4KMPSWeightPackOrder(axes: ["o", "i", "h", "w"])

	static func fromEnvironment(_ env: [String: String]) -> A4KMPSWeightPackOrder {
		guard let raw = env["A4K_MPS_WEIGHT_PACK"]?.lowercased(),
			  let parsed = parse(raw) else {
			return .ohwi
		}
		return parsed
	}

	func cacheTag() -> String {
		String(axes)
	}

	func mpsWeightsLayout() -> MPSCNNConvolutionWeightsLayout {
		// Current Apple SDK support is OHWI-only for MPSCNNConvolutionDataSource.
		return .OHWI
	}

	func packedIndex(outChannel: Int,
					 inChannel: Int,
					 y: Int,
					 x: Int) -> Int {
		let dimValues: [Character: Int] = [
			"o": outChannel,
			"i": inChannel,
			"h": y,
			"w": x
		]
		let dimExtents: [Character: Int] = [
			"o": 4,
			"i": 4,
			"h": 3,
			"w": 3
		]

		var index = 0
		for axis in axes {
			let extent = dimExtents[axis] ?? 1
			let value = dimValues[axis] ?? 0
			index = (index * extent) + value
		}
		return index
	}

	private static func parse(_ raw: String) -> A4KMPSWeightPackOrder? {
		guard raw.count == 4 else {
			return nil
		}

		let chars = Array(raw)
		let allowed: Set<Character> = ["o", "i", "h", "w"]
		let set = Set(chars)
		guard set == allowed else {
			return nil
		}

		return A4KMPSWeightPackOrder(axes: chars)
	}
}

private enum A4KMPSEquivalenceInputMode {
	case auto
	case unit
	case signed

	static func fromEnvironment(_ env: [String: String]) -> A4KMPSEquivalenceInputMode {
		switch env["A4K_MPS_EQ_INPUT_MODE"]?.lowercased() {
		case "unit", "unsigned", "0to1":
			return .unit
		case "signed", "neg1to1":
			return .signed
		default:
			return .auto
		}
	}

	func resolve(firstInputTextureName: String) -> A4KMPSEquivalenceInputMode {
		switch self {
		case .auto:
			return firstInputTextureName.uppercased() == "MAIN" ? .unit : .signed
		case .unit, .signed:
			return self
		}
	}

	func cacheTag() -> String {
		switch self {
		case .auto:
			return "auto"
		case .unit:
			return "unit"
		case .signed:
			return "signed"
		}
	}
}

private enum A4KMPSEquivalencePattern: String {
	case random
	case horizontalRamp = "h_ramp"
	case verticalRamp = "v_ramp"
	case checkerboard
	case stepX = "step_x"
}

private enum A4KMPSEquivalencePatternSet {
	case randomOnly
	case structured
	case mixed

	static func fromEnvironment(_ env: [String: String]) -> A4KMPSEquivalencePatternSet {
		switch env["A4K_MPS_EQ_PATTERNS"]?.lowercased() {
		case "random", "random-only", "random_only":
			return .randomOnly
		case "structured", "deterministic":
			return .structured
		default:
			return .mixed
		}
	}

	func patterns() -> [A4KMPSEquivalencePattern] {
		switch self {
		case .randomOnly:
			return [.random]
		case .structured:
			return [.stepX, .checkerboard, .horizontalRamp, .verticalRamp]
		case .mixed:
			return [.random, .stepX, .checkerboard, .horizontalRamp, .verticalRamp]
		}
	}

	func cacheTag() -> String {
		switch self {
		case .randomOnly:
			return "random"
		case .structured:
			return "structured"
		case .mixed:
			return "mixed"
		}
	}
}

private struct A4KMPSMappingCandidate {
	let weightLayout: A4KMPSWeightLayout
	let weightPackOrder: A4KMPSWeightPackOrder
	let inputChannelOrder: A4KMPSChannelOrder
	let outputChannelOrder: A4KMPSChannelOrder
	let flipKernelX: Bool
	let flipKernelY: Bool
	let offsetX: Int
	let offsetY: Int

	func cacheTag() -> String {
		let flipTag = "\(flipKernelX ? 1 : 0)\(flipKernelY ? 1 : 0)"
		let offsetTag = "\(offsetX),\(offsetY)"
		return "layout=\(weightLayout.cacheTag())|pack=\(weightPackOrder.cacheTag())|in=\(inputChannelOrder.cacheTag())|out=\(outputChannelOrder.cacheTag())|flip=\(flipTag)|offset=\(offsetTag)"
	}
}

private struct A4KMPSPlannerConfig {
	let enabled: Bool
	let validateEquivalence: Bool
	let validationSampleSize: Int
	let equivalenceMaxAbs: Float
	let equivalenceMeanAbs: Float
	let equivalenceBorderIgnore: Int
	let maxPlans: Int?
	let includePasses: Set<Int>?
	let weightLayout: A4KMPSWeightLayout
	let weightPackOrder: A4KMPSWeightPackOrder
	let channelOrder: A4KMPSChannelOrder
	let equivalenceInputMode: A4KMPSEquivalenceInputMode
	let equivalencePatternSet: A4KMPSEquivalencePatternSet
	let flipKernelX: Bool
	let flipKernelY: Bool
	let offsetX: Int
	let offsetY: Int
	let autoMapCandidates: Bool
	let autoMapOffsets: Bool
	let autoMapChannelPermutations: Bool

	static func fromEnvironment() -> A4KMPSPlannerConfig {
		let env = ProcessInfo.processInfo.environment
		let enabled = env["A4K_ENABLE_MPS_CONV"] == "1"
		let validateEquivalence = (env["A4K_MPS_VALIDATE_EQUIVALENCE"] ?? "1") != "0"
		let sampleSize = max(8, min(128, Int(env["A4K_MPS_EQ_SAMPLE_SIZE"] ?? "64") ?? 64))
		let maxAbs = Float(env["A4K_MPS_EQ_MAX_ABS"] ?? "0.003") ?? 0.003
		let meanAbs = Float(env["A4K_MPS_EQ_MEAN_ABS"] ?? "0.0005") ?? 0.0005
		let borderIgnore = max(0, min(4, Int(env["A4K_MPS_EQ_BORDER_IGNORE"] ?? "0") ?? 0))
		let maxPlans = env["A4K_MPS_MAX_PLANS"].flatMap(Int.init)
		let includePasses = parsePassList(env["A4K_MPS_INCLUDE_PASSES"])
		let weightLayout = A4KMPSWeightLayout.fromEnvironment(env)
		let weightPackOrder = A4KMPSWeightPackOrder.fromEnvironment(env)
		let channelOrder = A4KMPSChannelOrder.fromEnvironment(env)
		let equivalenceInputMode = A4KMPSEquivalenceInputMode.fromEnvironment(env)
		let equivalencePatternSet = A4KMPSEquivalencePatternSet.fromEnvironment(env)
		let flipKernelX = (env["A4K_MPS_FLIP_KERNEL_X"] ?? "0") == "1"
		let flipKernelY = (env["A4K_MPS_FLIP_KERNEL_Y"] ?? "0") == "1"
		let offsetX = max(0, min(2, Int(env["A4K_MPS_OFFSET_X"] ?? "0") ?? 0))
		let offsetY = max(0, min(2, Int(env["A4K_MPS_OFFSET_Y"] ?? "0") ?? 0))
		let autoMapCandidates = (env["A4K_MPS_AUTO_MAP"] ?? "1") != "0"
		let autoMapOffsets = (env["A4K_MPS_AUTO_OFFSET"] ?? "0") != "0"
		let autoMapChannelPermutations = (env["A4K_MPS_AUTO_CHANNEL_PERM"] ?? "1") != "0"

		return A4KMPSPlannerConfig(
			enabled: enabled,
			validateEquivalence: validateEquivalence,
			validationSampleSize: sampleSize,
			equivalenceMaxAbs: maxAbs,
			equivalenceMeanAbs: meanAbs,
			equivalenceBorderIgnore: borderIgnore,
			maxPlans: maxPlans,
			includePasses: includePasses,
			weightLayout: weightLayout,
			weightPackOrder: weightPackOrder,
			channelOrder: channelOrder,
			equivalenceInputMode: equivalenceInputMode,
			equivalencePatternSet: equivalencePatternSet,
			flipKernelX: flipKernelX,
			flipKernelY: flipKernelY,
			offsetX: offsetX,
			offsetY: offsetY,
			autoMapCandidates: autoMapCandidates,
			autoMapOffsets: autoMapOffsets,
			autoMapChannelPermutations: autoMapChannelPermutations
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
	private let weightsLayoutValue: MPSCNNConvolutionWeightsLayout

	init(label: String,
		 kernelWidth: Int,
		 kernelHeight: Int,
		 inputFeatureChannels: Int,
		 outputFeatureChannels: Int,
		 weightsLayout: MPSCNNConvolutionWeightsLayout,
		 weights: [Float],
		 bias: [Float]) {
		self.labelValue = label
		self.weightsCount = weights.count
		self.weightsLayoutValue = weightsLayout
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

	func weightsLayout() -> MPSCNNConvolutionWeightsLayout {
		weightsLayoutValue
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

			let resolvedInputMode = config.equivalenceInputMode.resolve(
				firstInputTextureName: metadata.inputTextureNames[0]
			)

			let functionName = metadata.functionName
			guard let section = sectionForFunction(functionName: functionName, in: metalSource) else {
				continue
			}

			if section.contains("go_1(") || section.contains("go_2(") || section.contains("go_3(") {
				continue
			}

			let baseCandidate = A4KMPSMappingCandidate(
				weightLayout: config.weightLayout,
				weightPackOrder: config.weightPackOrder,
				inputChannelOrder: config.channelOrder,
				outputChannelOrder: config.channelOrder,
				flipKernelX: config.flipKernelX,
				flipKernelY: config.flipKernelY,
				offsetX: config.offsetX,
				offsetY: config.offsetY
			)
			let candidates = mappingCandidates(config: config)

			var acceptedPlan: A4KMPSPassPlan?
			var acceptedCandidate: A4KMPSMappingCandidate?
			var bestRejected: (
				candidate: A4KMPSMappingCandidate,
				validation: (accepted: Bool, maxAbs: Float, meanAbs: Float, worstPattern: String)
			)?

			for candidate in candidates {
				guard let parsed = parseSingleInput3x3Pass(
					section: section,
					weightLayout: candidate.weightLayout,
					weightPackOrder: candidate.weightPackOrder,
					inputChannelOrder: candidate.inputChannelOrder,
					outputChannelOrder: candidate.outputChannelOrder,
					flipKernelX: candidate.flipKernelX,
					flipKernelY: candidate.flipKernelY
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
					weightsLayout: candidate.weightPackOrder.mpsWeightsLayout(),
					weights: parsed.packedWeights,
					bias: parsed.bias
				)

				let convolution = MPSCNNConvolution(device: device, weights: dataSource)
				convolution.accumulatorPrecisionOption = .float
				convolution.edgeMode = .clamp
				convolution.offset = MPSOffset(x: candidate.offsetX, y: candidate.offsetY, z: 0)

				let plan = A4KMPSPassPlan(dataSource: dataSource, convolution: convolution)

				if config.validateEquivalence {
					let validation = validatePlanEquivalence(
						device: device,
						library: library,
						functionName: functionName,
						plan: plan,
						inputMode: resolvedInputMode,
						patternSet: config.equivalencePatternSet,
						sampleSize: config.validationSampleSize,
						borderIgnore: config.equivalenceBorderIgnore,
						maxAbsThreshold: config.equivalenceMaxAbs,
						meanAbsThreshold: config.equivalenceMeanAbs
					)

					if validation.accepted {
						acceptedPlan = plan
						acceptedCandidate = candidate
						break
					}

					if let existing = bestRejected {
						if validationIsBetter(validation, than: existing.validation) {
							bestRejected = (candidate, validation)
						}
					} else {
						bestRejected = (candidate, validation)
					}

					continue
				}

				acceptedPlan = plan
				acceptedCandidate = candidate
				break
			}

			guard let acceptedPlan else {
				if let bestRejected {
					NSLog("[Anime4KMPS] Skipping %@ pass %d (%@): equivalence failed (mode=%@ patterns=%@ worst=%@ candidate=%@ border=%d maxAbs=%.6f meanAbs=%.6f)",
						  shaderFileName,
						  metadata.passIndex,
						  functionName,
						  resolvedInputMode.cacheTag(),
						  config.equivalencePatternSet.cacheTag(),
						  bestRejected.validation.worstPattern,
						  bestRejected.candidate.cacheTag(),
						  config.equivalenceBorderIgnore,
						  bestRejected.validation.maxAbs,
						  bestRejected.validation.meanAbs)
				}
				continue
			}

			if let acceptedCandidate,
			   acceptedCandidate.cacheTag() != baseCandidate.cacheTag() {
				NSLog("[Anime4KMPS] Pass %d (%@) selected tuned mapping: %@ (default=%@)",
					  metadata.passIndex,
					  functionName,
					  acceptedCandidate.cacheTag(),
					  baseCandidate.cacheTag())
			}

			plans[metadata.passIndex] = acceptedPlan
		}

		if plans.isEmpty {
			NSLog("[Anime4KMPS] Enabled, but no parity-safe single-input 3x3 passes found for %@", shaderFileName)
		} else {
			NSLog("[Anime4KMPS] Built %d parity-safe pass plan(s) for %@", plans.count, shaderFileName)
		}

		return plans
	}

	private static func mappingCandidates(config: A4KMPSPlannerConfig) -> [A4KMPSMappingCandidate] {
		let baseCandidate = A4KMPSMappingCandidate(
			weightLayout: config.weightLayout,
			weightPackOrder: config.weightPackOrder,
			inputChannelOrder: config.channelOrder,
			outputChannelOrder: config.channelOrder,
			flipKernelX: config.flipKernelX,
			flipKernelY: config.flipKernelY,
			offsetX: config.offsetX,
			offsetY: config.offsetY
		)

		guard config.autoMapCandidates else {
			return [baseCandidate]
		}

		var candidates: [A4KMPSMappingCandidate] = [baseCandidate]
		var seen = Set<String>([baseCandidate.cacheTag()])

		let weightLayouts = A4KMPSWeightLayout.allCases
		let weightPacks = [A4KMPSWeightPackOrder.ohwi, .oihw]
		let inputChannelOrders: [A4KMPSChannelOrder] = config.autoMapChannelPermutations
			? A4KMPSChannelOrder.allPermutations()
			: [.rgba, .bgra, .argb, .abgr]
		let flips = [false, true]

		let offsetXs = config.autoMapOffsets
			? Array(Set([config.offsetX, 0, 1])).sorted()
			: [config.offsetX]
		let offsetYs = config.autoMapOffsets
			? Array(Set([config.offsetY, 0, 1])).sorted()
			: [config.offsetY]

		for layout in weightLayouts {
			for pack in weightPacks {
				for inputChannel in inputChannelOrders {
					let outputHypotheses = outputChannelHypotheses(
						inputChannelOrder: inputChannel,
						config: config
					)

					for outputChannel in outputHypotheses {
						for flipX in flips {
							for flipY in flips {
								for offsetX in offsetXs {
									for offsetY in offsetYs {
										let candidate = A4KMPSMappingCandidate(
											weightLayout: layout,
											weightPackOrder: pack,
											inputChannelOrder: inputChannel,
											outputChannelOrder: outputChannel,
											flipKernelX: flipX,
											flipKernelY: flipY,
											offsetX: offsetX,
											offsetY: offsetY
										)

										let tag = candidate.cacheTag()
										if seen.insert(tag).inserted {
											candidates.append(candidate)
										}
									}
								}
							}
						}
					}
				}
			}
		}

		return candidates
	}

	private static func outputChannelHypotheses(
		inputChannelOrder: A4KMPSChannelOrder,
		config: A4KMPSPlannerConfig
	) -> [A4KMPSChannelOrder] {
		var candidates: [A4KMPSChannelOrder] = [
			config.channelOrder,
			.rgba
		]

		if config.autoMapChannelPermutations {
			candidates.append(inputChannelOrder)
			candidates.append(inputChannelOrder.inverse())
		} else {
			candidates.append(contentsOf: [.bgra, .argb, .abgr])
		}

		var seen = Set<String>()
		var deduped: [A4KMPSChannelOrder] = []
		for order in candidates {
			if seen.insert(order.cacheTag()).inserted {
				deduped.append(order)
			}
		}
		return deduped
	}

	private static func validationIsBetter(
		_ lhs: (accepted: Bool, maxAbs: Float, meanAbs: Float, worstPattern: String),
		than rhs: (accepted: Bool, maxAbs: Float, meanAbs: Float, worstPattern: String)
	) -> Bool {
		if lhs.maxAbs != rhs.maxAbs {
			return lhs.maxAbs < rhs.maxAbs
		}
		return lhs.meanAbs < rhs.meanAbs
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
									inputChannelOrder: A4KMPSChannelOrder,
									outputChannelOrder: A4KMPSChannelOrder,
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
						let mappedInChannel = inputChannelOrder.map(inChannel)
						let mappedOutChannel = outputChannelOrder.map(outChannel)

						let matrixValue: Float
						switch weightLayout {
						case .columnMajor:
							matrixValue = matrix[mappedInChannel * 4 + mappedOutChannel]
						case .rowMajor:
							matrixValue = matrix[mappedOutChannel * 4 + mappedInChannel]
						}

						let packedIndex = weightPackOrder.packedIndex(
							outChannel: outChannel,
							inChannel: inChannel,
							y: y,
							x: x
						)

						packedWeights[packedIndex] = matrixValue
					}
				}
			}
		}

		var mappedBias = [Float](repeating: 0, count: 4)
		for outChannel in 0..<4 {
			mappedBias[outChannel] = bias[outputChannelOrder.map(outChannel)]
		}

		return A4KValidatedMPSWeights(packedWeights: packedWeights, bias: mappedBias)
	}

	private static func parseFloatList(_ raw: String) -> [Float] {
		raw
			.split(separator: ",")
			.compactMap { token in
				Float(token.trimmingCharacters(in: .whitespacesAndNewlines))
			}
	}

	private static func fillEquivalenceInputHalf(pattern: A4KMPSEquivalencePattern,
									inputMode: A4KMPSEquivalenceInputMode,
									sampleSize: Int,
									generator: inout A4KLCG,
									output: inout [UInt16]) {
		let sampleSizeSafe = max(1, sampleSize)
		let invSpan = 1.0 / Float(max(1, sampleSizeSafe - 1))

		for i in 0..<output.count {
			let pixelIndex = i / 4
			let channel = i & 3
			let x = pixelIndex % sampleSizeSafe
			let y = pixelIndex / sampleSizeSafe

			if inputMode == .unit && channel == 3 {
				// MAIN decode path is opaque BGRA in practice; probing with random alpha
				// causes false negatives that do not reflect runtime behavior.
				output[i] = Float16(1.0).bitPattern
				continue
			}

			let baseUnit: Float
			switch pattern {
			case .random:
				baseUnit = generator.nextUnit()
			case .horizontalRamp:
				baseUnit = Float(x) * invSpan
			case .verticalRamp:
				baseUnit = Float(y) * invSpan
			case .checkerboard:
				baseUnit = ((x + y) & 1) == 0 ? 0.875 : 0.125
			case .stepX:
				baseUnit = x < (sampleSizeSafe / 2) ? 0.1 : 0.9
			}

			let channelOffset = Float(channel) * 0.02
			let unitValue = min(max((baseUnit * 0.94) + channelOffset, 0), 1)

			let value: Float
			switch inputMode {
			case .unit:
				value = unitValue
			case .signed, .auto:
				value = min(max((unitValue * 2.0) - 1.0, -1.0), 1.0)
			}

			output[i] = Float16(value).bitPattern
		}
	}

	private static func validatePlanEquivalence(device: MTLDevice,
									 library: MTLLibrary,
									 functionName: String,
									 plan: A4KMPSPassPlan,
									 inputMode: A4KMPSEquivalenceInputMode,
									 patternSet: A4KMPSEquivalencePatternSet,
									 sampleSize: Int,
									 borderIgnore: Int,
									 maxAbsThreshold: Float,
									 meanAbsThreshold: Float) -> (accepted: Bool, maxAbs: Float, meanAbs: Float, worstPattern: String) {
		guard let function = library.makeFunction(name: functionName),
			  let pipeline = try? device.makeComputePipelineState(function: function),
			  let inputTexture = makeSharedRGBA16Texture(device: device, width: sampleSize, height: sampleSize),
			  let referenceTexture = makeSharedRGBA16Texture(device: device, width: sampleSize, height: sampleSize),
			  let mpsTexture = makeSharedRGBA16Texture(device: device, width: sampleSize, height: sampleSize),
			  let commandQueue = device.makeCommandQueue() else {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, "setup")
		}

		guard let sampler = makeClampNearestSampler(device: device) else {
			return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, "setup")
		}

		var generator = A4KLCG(seed: 0xA4C54AFE)
		let pixelCount = sampleSize * sampleSize * 4
		let bytesPerRow = sampleSize * 4 * MemoryLayout<UInt16>.size
		var inputHalf = [UInt16](repeating: 0, count: pixelCount)
		var referenceHalf = [UInt16](repeating: 0, count: pixelCount)
		var mpsHalf = [UInt16](repeating: 0, count: pixelCount)
		let threadgroup = recommendedThreadgroupSize(for: pipeline)
		let grid = MTLSize(width: sampleSize, height: sampleSize, depth: 1)

		var worstMaxAbs: Float = 0
		var worstMeanAbs: Float = 0
		var worstPattern = A4KMPSEquivalencePattern.random
		let maxBorder = max(0, (sampleSize / 2) - 1)
		let safeBorderIgnore = max(0, min(maxBorder, borderIgnore))

		for pattern in patternSet.patterns() {
			fillEquivalenceInputHalf(
				pattern: pattern,
				inputMode: inputMode,
				sampleSize: sampleSize,
				generator: &generator,
				output: &inputHalf
			)

			inputHalf.withUnsafeBytes { raw in
				guard let base = raw.baseAddress else { return }
				inputTexture.replace(region: MTLRegionMake2D(0, 0, sampleSize, sampleSize),
							mipmapLevel: 0,
							withBytes: base,
							bytesPerRow: bytesPerRow)
			}

			guard let referenceCB = commandQueue.makeCommandBuffer(),
				  let referenceEncoder = referenceCB.makeComputeCommandEncoder() else {
				return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, pattern.rawValue)
			}

			referenceEncoder.setComputePipelineState(pipeline)
			referenceEncoder.setSamplerState(sampler, index: 0)
			referenceEncoder.setTexture(inputTexture, index: 0)
			referenceEncoder.setTexture(referenceTexture, index: 1)
			referenceEncoder.dispatchThreads(grid, threadsPerThreadgroup: threadgroup)
			referenceEncoder.endEncoding()

			referenceCB.commit()
			referenceCB.waitUntilCompleted()
			if referenceCB.status == .error {
				return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, pattern.rawValue)
			}

			guard let mpsCB = commandQueue.makeCommandBuffer() else {
				return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, pattern.rawValue)
			}

			guard plan.encode(commandBuffer: mpsCB, sourceTexture: inputTexture, destinationTexture: mpsTexture) else {
				return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, pattern.rawValue)
			}

			mpsCB.commit()
			mpsCB.waitUntilCompleted()
			if mpsCB.status == .error {
				return (false, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, pattern.rawValue)
			}

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
			var comparedSamples = 0

			for pixelIndex in 0..<(sampleSize * sampleSize) {
				let x = pixelIndex % sampleSize
				let y = pixelIndex / sampleSize

				if safeBorderIgnore > 0,
				   (x < safeBorderIgnore ||
					y < safeBorderIgnore ||
					x >= (sampleSize - safeBorderIgnore) ||
					y >= (sampleSize - safeBorderIgnore)) {
					continue
				}

				for channel in 0..<4 {
					let index = pixelIndex * 4 + channel
					let ref = Float(Float16(bitPattern: referenceHalf[index]))
					let test = Float(Float16(bitPattern: mpsHalf[index]))
					let diff = abs(ref - test)
					maxAbs = max(maxAbs, diff)
					sumAbs += diff
					comparedSamples += 1
				}
			}

			if comparedSamples == 0 {
				for i in 0..<pixelCount {
					let ref = Float(Float16(bitPattern: referenceHalf[i]))
					let test = Float(Float16(bitPattern: mpsHalf[i]))
					let diff = abs(ref - test)
					maxAbs = max(maxAbs, diff)
					sumAbs += diff
				}
				comparedSamples = pixelCount
			}

			let meanAbs = sumAbs / Float(max(1, comparedSamples))
			if maxAbs > worstMaxAbs || meanAbs > worstMeanAbs {
				worstMaxAbs = maxAbs
				worstMeanAbs = meanAbs
				worstPattern = pattern
			}
		}

		let accepted = (worstMaxAbs <= maxAbsThreshold) && (worstMeanAbs <= meanAbsThreshold)
		return (accepted, worstMaxAbs, worstMeanAbs, worstPattern.rawValue)
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

	mutating func nextUnit() -> Float {
		let raw = nextUInt32()
		return Float(raw) / Float(UInt32.max)
	}

	mutating func nextSignedUnit() -> Float {
		let normalized = nextUnit()
		return (normalized * 2.0) - 1.0
	}
}