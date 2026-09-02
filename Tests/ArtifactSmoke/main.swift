import AnyDocSwiftBridge

var versionLength = 0
guard anydoc_swift_abi_version() == 3 else {
  fatalError("unexpected ABI version")
}
guard anydoc_swift_engine_version(&versionLength) != nil, versionLength > 0 else {
  fatalError("missing engine version")
}

var result = anydoc_swift_convert_markdown(nil, 0, nil, 0, 1_024, 1_024)
guard let markdownResult = result, anydoc_swift_result_kind(markdownResult) == 0 else {
  fatalError("missing Markdown failure result")
}
anydoc_swift_result_free(markdownResult)

result = anydoc_swift_convert_document(nil, 0, nil, 0, 1_024, 1_024)
guard let documentResult = result, anydoc_swift_result_kind(documentResult) == 0 else {
  fatalError("missing document failure result")
}
var bytes: UnsafePointer<UInt8>? = UnsafePointer(bitPattern: 1)
var length = Int.max
guard anydoc_swift_result_document_asset(documentResult, 0, &bytes, &length) == 0,
  bytes == nil, length == 0
else {
  fatalError("document asset mismatch did not reset outputs")
}
anydoc_swift_result_free(documentResult)
