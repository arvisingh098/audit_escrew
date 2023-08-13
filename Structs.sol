// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract Structs {
    struct Escrows {
        uint id;
        address assignor;
        address assignee;
        uint amount;
        string details;
        string title;
        ContractStatus status;
        bool token;
        address tokenAddress;
    }

    struct Dispute {
        uint escrowId;
        address assignor;
        address assignee;
        uint amount;
        string assignorDetails;
        string assigneeDetails;
        uint disputeCreateTime;
        uint validatorId;
        disputeLevel disputeLevel;
        string[] assignorProfs;
        string[] assigneeProfs;
        bool assigneeCreatedDispute;
    }

    struct Validators {
        uint disputeId;
        address[] validator;
        uint votesForAssignor;
        uint votesForAssignee;
        bool assignorWon;
        bool assigneeWon;
        bool draw;
        bool nextChance;
        bool start;
    }

    enum ContractStatus {
        created,
        accepted,
        completed,
        approved,
        cancelled,
        disputed,
        disputedlevel2,
        closed
    }
    enum disputeLevel {
        level1,
        level2
    }
    
}
