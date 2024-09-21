// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ProposalEscrow is ReentrancyGuard {
    enum ProposalStatus {
        None,
        BriefSent,
        ProposalSent,
        Accepted,
        Rejected,
        CancelledByCustomer,
        CancelledByTalent
    }

    struct Proposal {
        uint256 customerEscrow;
        uint256 talentEscrow;
        uint256 createdAt;
        address customer;
        address talent;
        uint8 status; // Using uint8 to save gas
    }

    uint256 public proposalCounter;
    mapping(uint256 => Proposal) public proposals;
    uint256 public constant RESPONSE_TIME = 24 hours;

    event BriefSent(
        uint256 proposalId,
        address customer,
        address talent,
        uint256 escrowAmount
    );
    event ProposalAccepted(
        uint256 proposalId,
        address talent,
        uint256 escrowAmount
    );
    event ProposalCancelledByCustomer(uint256 proposalId);
    event ProposalCancelledByTalent(uint256 proposalId);
    event ProposalAcceptedByCustomer(uint256 proposalId);
    event EscrowRefunded(
        uint256 proposalId,
        address recipient,
        uint256 amount
    );
    event EscrowTransferred(
        uint256 proposalId,
        address from,
        address to,
        uint256 amount
    );
    event UnexpectedDeposit(address indexed sender, uint256 amount);

    modifier onlyCustomer(uint256 _proposalId) {
        require(
            msg.sender == proposals[_proposalId].customer,
            "Only customer can call this function"
        );
        _;
    }

    modifier onlyTalent(uint256 _proposalId) {
        require(
            msg.sender == proposals[_proposalId].talent,
            "Only talent can call this function"
        );
        _;
    }

    modifier inStatus(uint256 _proposalId, ProposalStatus _status) {
        require(
            proposals[_proposalId].status == uint8(_status),
            "Invalid proposal status for this action"
        );
        _;
    }

    function sendBrief(address _talent) external payable nonReentrant {
        require(msg.value > 0, "Escrow amount must be greater than zero");
        proposalCounter++;
        proposals[proposalCounter] = Proposal({
            customerEscrow: msg.value,
            talentEscrow: 0,
            createdAt: block.timestamp,
            customer: msg.sender,
            talent: _talent,
            status: uint8(ProposalStatus.BriefSent)
        });
        emit BriefSent(proposalCounter, msg.sender, _talent, msg.value);
    }

    function acceptBrief(uint256 _proposalId)
        external
        payable
        nonReentrant
        onlyTalent(_proposalId)
        inStatus(_proposalId, ProposalStatus.BriefSent)
    {
        require(msg.value > 0, "Talent escrow must be greater than zero");
        Proposal storage proposal = proposals[_proposalId];
        proposal.talentEscrow = msg.value;
        proposal.status = uint8(ProposalStatus.ProposalSent);
        proposal.createdAt = block.timestamp; // Update timestamp
        emit ProposalAccepted(_proposalId, msg.sender, msg.value);
    }

    function acceptProposal(uint256 _proposalId)
        external
        nonReentrant
        onlyCustomer(_proposalId)
        inStatus(_proposalId, ProposalStatus.ProposalSent)
    {
        Proposal storage proposal = proposals[_proposalId];

        uint256 customerAmount = proposal.customerEscrow;
        uint256 talentAmount = proposal.talentEscrow;

        // Update state before external calls to prevent reentrancy
        proposal.customerEscrow = 0;
        proposal.talentEscrow = 0;
        proposal.status = uint8(ProposalStatus.Accepted);

        // Transfer funds back to both parties
        safeTransfer(proposal.customer, customerAmount);
        safeTransfer(proposal.talent, talentAmount);

        emit EscrowRefunded(_proposalId, proposal.customer, customerAmount);
        emit EscrowRefunded(_proposalId, proposal.talent, talentAmount);
        emit ProposalAcceptedByCustomer(_proposalId);
    }

    function cancelProposalByCustomer(uint256 _proposalId)
        external
        nonReentrant
        onlyCustomer(_proposalId)
    {
        Proposal storage proposal = proposals[_proposalId];
        require(
            proposal.status == uint8(ProposalStatus.BriefSent) ||
                proposal.status == uint8(ProposalStatus.ProposalSent),
            "Cannot cancel at this stage"
        );

        uint256 amount = proposal.customerEscrow;
        address recipient;

        // Update state before external calls
        proposal.customerEscrow = 0;
        proposal.status = uint8(ProposalStatus.CancelledByCustomer);

        if (proposal.talentEscrow > 0) {
            // Transfer escrow to talent if they have accepted
            recipient = proposal.talent;
            emit EscrowTransferred(_proposalId, proposal.customer, proposal.talent, amount);
        } else {
            // Refund escrow to customer
            recipient = proposal.customer;
            emit EscrowRefunded(_proposalId, proposal.customer, amount);
        }

        // Transfer funds
        safeTransfer(recipient, amount);

        emit ProposalCancelledByCustomer(_proposalId);
    }

    function cancelProposalByTalent(uint256 _proposalId)
        external
        nonReentrant
        onlyTalent(_proposalId)
        inStatus(_proposalId, ProposalStatus.ProposalSent)
    {
        Proposal storage proposal = proposals[_proposalId];

        uint256 amount = proposal.talentEscrow;

        // Update state before external calls
        proposal.talentEscrow = 0;
        proposal.status = uint8(ProposalStatus.CancelledByTalent);

        // Transfer escrow to customer
        safeTransfer(proposal.customer, amount);

        emit EscrowTransferred(_proposalId, proposal.talent, proposal.customer, amount);
        emit ProposalCancelledByTalent(_proposalId);
    }

    function processTimeout(uint256 _proposalId)
        external
        nonReentrant
        onlyCustomer(_proposalId)
    {
        Proposal storage proposal = proposals[_proposalId];
        require(
            proposal.status == uint8(ProposalStatus.BriefSent),
            "Proposal is not awaiting talent response"
        );
        require(
            block.timestamp >= proposal.createdAt + RESPONSE_TIME,
            "Response time has not elapsed"
        );

        uint256 amount = proposal.customerEscrow;

        // Update state before external calls
        proposal.customerEscrow = 0;
        proposal.status = uint8(ProposalStatus.Rejected);

        // Refund customer escrow
        safeTransfer(proposal.customer, amount);

        emit EscrowRefunded(_proposalId, proposal.customer, amount);
    }

    // Receive function to handle unexpected ETH deposits
    receive() external payable {
        emit UnexpectedDeposit(msg.sender, msg.value);
    }

    // Safe transfer function to handle reentrancy and errors
    function safeTransfer(address recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Insufficient contract balance");
        (bool sent, ) = payable(recipient).call{value: amount}("");
        require(sent, "Failed to transfer funds");
    }
}
