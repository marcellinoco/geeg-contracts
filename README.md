Proposal Escrow Smart Contract [FLOW Testnet](https://evm-testnet.flowscan.io/address/0xa371E2F9A1EC41dE5F6bEEC2db02146cBC3ECEEF)
1. Talents need to escrow FLOW to be discoverable.
2. Client need to escrow FLOW when sending project requirements to matched talents.
3. Project brief are then sent to the respective talents, starting a countdown of 24h.
    - If the window has passed without the talent responding, escrowed value from talent will be sent to client for time compensation.
    - The talent won't be penalized if they rejected the brief during the window.
4. Talents are then required to send a proposal offer for the project to the client within a window.
    - If the window is not met, talent will be penalized.
    - If the client rejected the proposal, they may choose to settle or cancel the project, sending escrowed FLOW to talent, compensating for their effort creating proposal.
5. Once both parties are happy, the proposal will end and the escrowed FLOW will be returned.
