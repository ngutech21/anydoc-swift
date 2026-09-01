import AnyDocSwiftBridge

var versionLength = 0
guard anydoc_swift_abi_version() == 2 else {
  fatalError("unexpected ABI version")
}
guard anydoc_swift_engine_version(&versionLength) != nil, versionLength > 0 else {
  fatalError("missing engine version")
}
