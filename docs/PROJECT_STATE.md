# Project state

Phase: Sepolia deployment retry
Branch: main (primary checkout)
Code candidate: fe86f51d9816ac0cfe71396d4fca1b07049e5735
Product rules: [DESIGN.md](../DESIGN.md) and [SECURITY.md](../SECURITY.md)
Launch status: not deployed

The October 9, 2026 Sepolia attempt sent two transactions. Both receipts have status `0x0`:
renderer `0xcbe7439bf8778061ce95655a999147a726761f001cb45caf3f822f6abcd936ac`
and packs `0xe13c233398df4b01f919d3a80a3cd3173a979ac3cac2c16df0d3ea0148558bbb`.
Neither predicted address has code. The timestamped Foundry broadcast artifact remains in the
primary checkout; its duplicate `run-latest.json` and the invalid manifest were removed after
checking the receipts.

Sepolia's Glamsterdam code-deposit repricing caused the renderer to exhaust its 2,537,746 gas
limit. Tenderly estimated 13,874,050 gas for the same creation. Candidate `fe86f51` raises the
Sepolia gas multiplier, waits for each creation to succeed, and writes a manifest only after live
receipt and constructor-state checks. Its focused tests and `forge build` pass. The earlier full
default and testnet suites each passed 216 tests with no failures; runtime contract code is unchanged.

Next: the operator runs a dry run, then broadcasts from the primary `main` checkout using
Tenderly's public Sepolia RPC and the `ripe0x` keystore. Check the new manifest and onchain state
before treating Sepolia as deployed.
