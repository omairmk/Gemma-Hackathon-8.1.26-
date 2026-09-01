# LiteRT-LM v0.15 Swift wrapper provenance

This committed package vendors the production Swift wrapper from
`https://github.com/google-ai-edge/LiteRT-LM.git` at upstream commit
`2117fc4314670e00047bc8469783f02a68c33f0c` (upstream `swift` tree
`3c92652e515df4d56f5d22ed24bcd09854371358`). It remains Apache-2.0 licensed;
the unmodified upstream license is in `LICENSE`.

The iOS native binary remains the official v0.15.0 checksum-pinned artifact:

- URL: `https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM.xcframework.zip`
- SwiftPM checksum: `d6ccf6b54362d894ff71a7580c7e446d36767dab908aecfbb16ffca0fa0bc59b`

The macOS conditional binary retained from the upstream manifest is:

- URL: `https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM_mac.xcframework.zip`
- SwiftPM checksum: `d23cf189ce8f6bb2556c0a023805e245d1ec862434e501eb60f353488033c1b5`

GI Journal modifications are intentionally limited to:

- `Package.swift`: removes unused adapter and upstream test targets.
- `swift/Config.swift`: validates and exposes the native image-limit field and main CPU thread count.
- `swift/Engine.swift`: forwards those reviewed values to the existing v0.15 C setters.
- `swift/LiteRTLMError.swift`: adds the explicit CPU-thread validation error.

The raw-photo route sets `maxNumImages` to one, but the packaged v0.15 C header
documents that setter as legacy-only; it is not evidence that the advanced
engine is limited to one image or uses less memory. GI Journal separately keeps
its product route to one selected photo. The wrapper does not invent a CPU
thread count and does not claim control over the vision executor's thread count.

The path-independent SHA-256 over the ordered production compile-input digest
list is `22c81184a1bad821ea7c890c167fa0a75089ba774beaf8176a0d3b99290d842d`.

## Current committed-source SHA-256 values

```text
2b0198141da34376a445942a3e93ca0a4eb9f16c811d3d342ac3d3d4947d4428  Package.swift
c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4  LICENSE
9096200cb1ad930cb6ac9af72747c430621739838b9f18ec8d3b2ea4fce7fd74  swift/Benchmark.swift
30bc7cd1057f9100ef19249863266481a61e4c80d2a28ccb6098236318dee020  swift/Capabilities.swift
721289dc0bc213c2371119eaf49e24b6d5324572990c6ac2a9de1926423731da  swift/Config.swift
49701ac6c3856bb921e191a260fb19e58ec49b2f057a211093796dffc22e6b9e  swift/Conversation.swift
098853a2a0ba79ed2b3ced53799178b86579619c0de8a3b67e7006239325514b  swift/Engine.swift
e7aa8ed306d0ab5c84557512da020a140af4c7b90c4d8cb54a53f585182fdbfc  swift/ExperimentalFlags.swift
35226ebc4ba514db9f886bc2153ba3de93e9a500d3f4c2946a87f177069441b2  swift/LiteRTLMError.swift
23631912d2caf0a63f971e5da869ef9e385fa1b93e459e1ea3232cc6a99fa637  swift/Message.swift
071705a8d9e9916a83b2197514d58bdbd3a30e643903a9e826a500fb67772067  swift/ResponseFormat.swift
d9698c6c7f8425cfa1f479cec5070fe94d9ca732b3e20b171e3dd90ca1545422  swift/Tool.swift
7fed45d66e562a153dd61e57a8cc67cbd89fa063d1c09d9d20626ea48574d3f7  swift/ToolManager.swift
```

For the four modified upstream files, the pre-modification upstream SHA-256
values were `1c9191faebdb6cc5117b6ac9b54a76381652f60ca70618d0d83d3dfdb99341cd`
(`Package.swift`), `ebf04d01b716b7af896b7d37e3138f47050a0d6a6cc5ecaba065866a575b62fa`
(`Config.swift`), `7124ee34adf23c152ffe5716148971f7348a3c1fc9ce18102645730e6f885386`
(`Engine.swift`), and `720ee53b1de10d9be497c6962515549038d4f8653260b16011bd352de71cad2e`
(`LiteRTLMError.swift`). Each modified file carries an inline modification
notice in addition to this provenance ledger.
