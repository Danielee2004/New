# Micro-Lending Pool — Clarity-only Smart Contract

A compact on-chain micro-lending pool implemented purely in Clarity for the Stacks blockchain.

Key ideas:
- Community-funded treasury accepts micro-contributions.
- Borrowers deposit STX collateral and request loans that are auto-approved when collateral ≥ configured collateralization ratio.
- Interest accrues per block; repayments return collateral.
- Loans can be liquidated if overdue or under-collateralized.
- All logic runs on-chain — no off-chain components, no frontend required.

Why this is competition-ready:
- Social impact: enables micro-credit in a permissionless, transparent manner.
- Technical composition: demonstrates custody, automated lending, interest math, and liquidation logic — all on-chain.
- Compact and auditable: the whole project is a single Clarity contract + tests, ideal for demos and security review.

Included:
- `contracts/micro-lending.clar` — Clarity smart contract
- `tests/micro_lending_test.ts` — Clarinet test scaffold
