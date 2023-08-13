// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract Events {
    event ContractCreated(
        uint indexed id,
        address indexed assignor,
        address indexed assignee
    );
    event ContractAccepted(
        uint indexed id,
        address indexed assignor,
        address indexed assignee
    );
    event ContractCompleted(
        uint indexed id,
        address indexed assignor,
        address indexed assignee
    );

    event ContractEnded(
        uint indexed id,
        address indexed assignor,
        address indexed assignee
    );
    event ContractCancelled(
        uint indexed id,
        address indexed assignor,
        address indexed assignee
    );
    event DisputeCreated(
        uint indexed id,
        address indexed assignor,
        address indexed assignee
    );
}