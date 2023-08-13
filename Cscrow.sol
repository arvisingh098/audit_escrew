// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./Events.sol";
import "./Structs.sol";

contract Cscrow is Initializable, Events, Structs {
    address public owner;
    uint public totalEscrows;
    uint public companyProfit;
    uint public totalDisputes;
    uint public totalValidators;

    mapping(uint => Escrows) public escrows;
    mapping(uint => Dispute) public disputes;
    mapping(uint => Validators) public validators;
    mapping(address => uint) public points;
    mapping(address => bool) public enabledTokens;

    function initialize() public initializer {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    function contractExist(uint _id) private view {
        require(_id <= totalEscrows, "CNE");
    }

    function onlyAssignee(uint _id) private view {
        require(escrows[_id].assignee == msg.sender, "not authorized");
    }

    function onlyAssigner(uint _id) private view {
        require(escrows[_id].assignor == msg.sender);
    }

    function bothParties(uint _disputeId) private view {
        require(
            disputes[_disputeId].assignee == msg.sender ||
                disputes[_disputeId].assignor == msg.sender,
            "Not authorized"
        );
    }

    function checkStatus(uint _id, ContractStatus _status) private view {
        require(escrows[_id].status == _status, "Not accepted");
    }

    function createContract(
        address _assignee,
        uint _amount,
        string memory _details,
        string memory _title,
        bool _token,
        address _tokenAddress
    ) public payable {
        require(_assignee != address(0), "Invalid address");
        require(_amount > 0, "Amount < 0");
        ContractStatus status = ContractStatus.created;
        if (_token) {
            require(isTokenEnabled(_tokenAddress), "Token not enabled");
            IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);

            require(
                token.allowance(msg.sender, address(this)) >= _amount,
                "low allowance"
            );
            require(token.balanceOf(msg.sender) >= _amount, "low balance");
            token.transferFrom(msg.sender, address(this), _amount);
        } else {
            require(msg.value >= _amount, "low funds");
        }

        Escrows memory tmpEscrow = Escrows(
            totalEscrows,
            msg.sender,
            _assignee,
            _amount,
            _details,
            _title,
            status,
            _token,
            _tokenAddress
        );
        escrows[totalEscrows] = tmpEscrow;
        emit ContractCreated(totalEscrows, msg.sender, _assignee);
        totalEscrows += 1;
    }

    function withdrawContract(uint _id) public {
        onlyAssigner(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.created);
        escrows[_id].status = ContractStatus.closed;
        sendFundsAfterValidation(
            _id,
            escrows[_id].amount,
            escrows[_id].assignor
        );
    }

    function acceptContract(uint _id) public {
        onlyAssignee(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.created);
        escrows[_id].status = ContractStatus.accepted;
        emit ContractAccepted(
            _id,
            escrows[_id].assignor,
            escrows[_id].assignee
        );
    }

    function notAcceptContract(uint _id) public {
        onlyAssignee(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.created);
        escrows[_id].status = ContractStatus.cancelled;
        emit ContractCancelled(
            _id,
            escrows[_id].assignor,
            escrows[_id].assignee
        );
    }

    function completeContract(uint _id) public {
        onlyAssignee(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.accepted);
        escrows[_id].status = ContractStatus.completed;
        emit ContractCompleted(
            _id,
            escrows[_id].assignor,
            escrows[_id].assignee
        );
    }

    function approveContract(uint _id) public {
        onlyAssigner(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.completed);

        uint amount = escrows[_id].amount;
        uint commission = (amount * 2) / 100;
        uint assigneeAmount = amount - commission;

        companyProfit = companyProfit + commission;
        sendFundsAfterValidation(_id, assigneeAmount, escrows[_id].assignee);
        escrows[_id].status = ContractStatus.approved;
        emit ContractEnded(_id, escrows[_id].assignor, escrows[_id].assignee);
    }

    function createDisputeLevel1(
        uint _id,
        uint _amount,
        string memory _details
    ) external {
        onlyAssigner(_id);
        contractExist(_id);
        onlyAssignee(_id);
        checkStatus(_id, ContractStatus.accepted);
        escrows[_id].status = ContractStatus.disputed;
        string[] memory assigneeProfs;
        string[] memory assignorProfs;
        bool whoCreated;
        if (msg.sender == escrows[_id].assignee) {
            whoCreated = true;
        }
        Dispute memory dispute = Dispute(
            _id,
            escrows[_id].assignor,
            escrows[_id].assignee,
            _amount,
            _details,
            "",
            0,
            totalValidators,
            disputeLevel.level1,
            assignorProfs,
            assigneeProfs,
            whoCreated
        );

        disputes[totalDisputes] = dispute;
        totalDisputes += 1;
    }

    function acceptDispute(uint _disputeId) public {
        require(
            disputes[_disputeId].disputeLevel == disputeLevel.level1,
            "Not created"
        );
        bothParties(_disputeId);
        uint ecsrowId = disputes[_disputeId].escrowId;
        contractExist(ecsrowId);
        checkStatus(ecsrowId, ContractStatus.disputed);

        escrows[ecsrowId].status = ContractStatus.closed;

        uint amount = escrows[ecsrowId].amount;
        uint commission = (amount * 2) / 100;
        uint remaining = amount - commission;
        uint secondPartyAmount = remaining - disputes[_disputeId].amount;

        sendFundsAfterValidation(
            ecsrowId,
            disputes[_disputeId].amount,
            msg.sender
        );
        if (secondPartyAmount > 0) {
            address sendingAddress;
            if (disputes[_disputeId].assigneeCreatedDispute) {
                sendingAddress = escrows[ecsrowId].assignor;
            } else {
                sendingAddress = escrows[ecsrowId].assignee;
            }
            sendFundsAfterValidation(
                ecsrowId,
                secondPartyAmount,
                sendingAddress
            );
        }

        companyProfit = companyProfit + commission;

        emit ContractCancelled(
            ecsrowId,
            escrows[ecsrowId].assignor,
            escrows[ecsrowId].assignee
        );
    }

    function createDisputeLevel2(
        uint _disputeId,
        string memory _details,
        string[] memory _profs
    ) external {
        require(_disputeId <= totalDisputes, "DNE");

        bothParties(_disputeId);
        uint ecsrowId = disputes[_disputeId].escrowId;
        checkStatus(ecsrowId, ContractStatus.disputed);
        disputes[_disputeId].disputeCreateTime = block.timestamp;
        disputes[_disputeId].disputeLevel = disputeLevel.level2;
        addProfs(_disputeId, _details, _profs);
    }

    function addProofsForDisputeLevel2(
        uint _disputeId,
        string memory _details,
        string[] memory _profs
    ) external {
        require(_disputeId <= totalDisputes, "DNE");
        require(
            disputes[_disputeId].disputeLevel == disputeLevel.level2,
            "Not created"
        );
        bothParties(_disputeId);
        addProfs(_disputeId, _details, _profs);
        checkStatus(disputes[_disputeId].escrowId, ContractStatus.disputed);
        address[] memory _validators;

        Validators memory tmpValidate = Validators(
            _disputeId,
            _validators,
            0,
            0,
            false,
            false,
            false,
            false,
            false
        );

        validators[totalValidators] = tmpValidate;
    }

    function addProfs(
        uint _disputeId,
        string memory _details,
        string[] memory _profs
    ) internal {
        bothParties(_disputeId);
        if (msg.sender == disputes[_disputeId].assignee) {
            disputes[_disputeId].assigneeProfs = _profs;
            disputes[_disputeId].assigneeDetails = _details;
        } else {
            disputes[_disputeId].assigneeProfs = _profs;
            disputes[_disputeId].assignorDetails = _details;
        }
    }

    function validate(uint _validateId, uint voteFor) public {
        require(_validateId <= totalValidators, "VNE");
        require(validators[_validateId].disputeId <= totalDisputes, "DNE");
        require(!alreadyVoted(_validateId), "Already voted");
        if (voteFor == 0) {
            validators[_validateId].votesForAssignor += 1;
        } else if (voteFor == 1) {
            validators[_validateId].votesForAssignee += 1;
        }
        validators[_validateId].validator.push(msg.sender);
    }

    function resolveDispute(uint _disputeId) external onlyOwner {
        require(_disputeId <= totalDisputes, "DNE");
        uint validateId = disputes[_disputeId].validatorId;
        uint escrow = disputes[_disputeId].escrowId;
        uint amount = escrows[escrow].amount;
        uint disputeAmount = disputes[_disputeId].amount;

        uint commission = (amount * 2) / 100;
        uint validatorAmount = (amount * 10) / 100;

        uint remaining = amount - (commission + validatorAmount);

        uint amountToAssignee = remaining - disputeAmount;

        uint amountToParties = remaining / 2;

        require(
            disputes[_disputeId].disputeCreateTime + 24 hours <=
                block.timestamp,
            "Time remaining"
        );

        if (
            validators[validateId].votesForAssignor ==
            validators[validateId].votesForAssignee
        ) {
            if (!validators[validateId].nextChance) {
                disputes[_disputeId].disputeCreateTime = block.timestamp;
                validators[validateId].nextChance = true;
            } else {
                companyProfit = companyProfit + commission;
                validators[validateId].draw = true;
                sendFundsAfterValidation(
                    escrow,
                    amountToParties,
                    disputes[_disputeId].assignor
                );
                sendFundsAfterValidation(
                    escrow,
                    amountToParties,
                    disputes[_disputeId].assignee
                );
                sentCommissionToValidators(
                    validators[validateId].validator,
                    validatorAmount,
                    escrows[escrow].token,
                    escrows[escrow].tokenAddress
                );
            }
        } else {
            if (
                validators[validateId].votesForAssignor >
                validators[validateId].votesForAssignee
            ) {
                validators[validateId].assignorWon = true;
                sendFundsAfterValidation(
                    escrow,
                    disputeAmount,
                    disputes[_disputeId].assignor
                );
                if (disputeAmount > 0) {
                    sendFundsAfterValidation(
                        escrow,
                        amountToAssignee,
                        disputes[_disputeId].assignee
                    );
                }
            } else if (
                validators[validateId].votesForAssignor <
                validators[validateId].votesForAssignee
            ) {
                validators[validateId].assigneeWon = true;
                sendFundsAfterValidation(
                    escrow,
                    remaining,
                    disputes[_disputeId].assignee
                );
            }
            companyProfit = companyProfit + commission;
            sentCommissionToValidators(
                validators[validateId].validator,
                validatorAmount,
                escrows[escrow].token,
                escrows[escrow].tokenAddress
            );
        }

        escrows[escrow].status = ContractStatus.closed;
    }

    function sendFundsAfterValidation(
        uint _id,
        uint _amount,
        address _to
    ) internal {
        if (escrows[_id].token) {
            transferToken(escrows[_id].tokenAddress, _to, _amount);
        } else {
            transferNative(_to, _amount);
        }
    }

    function sentCommissionToValidators(
        address[] memory _address,
        uint _amount,
        bool _token,
        address _tokenAddress
    ) internal onlyOwner {
        uint perValidatorAmount = _amount / 10;
        if (_token) {
            for (uint i = 0; i < _address.length; i++) {
                if (i == 10) {
                    break;
                }
                transferToken(_tokenAddress, _address[i], perValidatorAmount);
            }
        } else {
            for (uint i = 0; i < _address.length; i++) {
                if (i == 10) {
                    break;
                }
                transferNative(_address[i], perValidatorAmount);
            }
        }
    }

    function transferNative(address _address, uint _amount) internal {
        require(_amount <= address(this).balance, "No Funds");
        (bool success, ) = _address.call{value: _amount}("");
        require(success, "Amount not sent");
    }

    function transferToken(
        address _tokenAddress,
        address _address,
        uint _amount
    ) internal {
        IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);
        require(_amount <= token.balanceOf(address(this)), "No Funds");
        token.transferFrom(address(this), _address, _amount);
    }

    function alreadyVoted(uint _id) public view returns (bool) {
        for (uint i = 0; i < validators[_id].validator.length; i++) {
            if (validators[_id].validator[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }

    function withdrawCompleteCommissionNative() public onlyOwner {
        transferNative(owner, companyProfit);
        companyProfit = 0;
    }

    function withdrawCompleteCommissionToken(address _token) public onlyOwner {
        transferToken(_token, owner, companyProfit);
        companyProfit = 0;
    }

    function getPoints(address _address) public view returns (uint) {
        return points[_address];
    }

    function addEnableTokens(address[] memory _tokens) public onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            enabledTokens[_tokens[i]] = true;
        }
    }

    function isTokenEnabled(address _token) public view returns (bool) {
        return enabledTokens[_token];
    }
}
