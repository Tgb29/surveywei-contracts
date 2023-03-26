// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IAttestationStation {
    struct AttestationData {
        address about;
        bytes32 key;
        bytes val;
    }

    function attest(AttestationData[] memory _attestations) external;

    function attestations(address _attester, address _subject, bytes32 _key) external view returns (bytes memory);
}

contract SurveyWei {

    using SafeMath for uint256;

    address attestStationAddress = 0xEE36eaaD94d1Cc1d0eccaDb55C38bFfB6Be06C77;

    uint256 minAttestations = 3;
    uint256 minRatio = 5;
    uint256 daysInSeconds = 7 * 24 * 60 * 60; //7 days

    enum SurveyStatus { Open, Closed }
    enum RespondentStatus { Started, Completed, Unfinished, DQ}

    struct Survey {
        string id;
        address creator;
        uint256 totalBounty;
        uint256 remainingBounty;
        uint256 respondents;
        SurveyStatus status;
        uint256 createdAt;
        uint256 timeLength;
        uint256 respondentsStarted;
        uint256 respondentsCompleted;
        uint256 respondentsClaimed;
        address[] active;
    }

    struct Respondent {
        uint256 respondentStartTime;
        uint256 respondentCompleteTime;
        RespondentStatus status;
        string answers;
        bool claimed;
        bool positive;
        bool negative;
    }

    mapping(string => Survey) public surveys;
    mapping(address => mapping(string => Respondent)) public respondents;

    event SurveyCreated(address indexed creator, string id);
    event SurveyClosed(address indexed creator, string id);
    event SurveyStarted(address indexed respondent, string id);
    event SurveyCompleted(address indexed respondent, string id);
    event TransferSuccessful(address indexed _to, uint256 _value);
    event AttestationSubmitted(bytes32 _attestation, address indexed _subject);

    function createSurvey(string memory _id, uint256 _bounty, uint256 _respondents, uint256 _timeLength) payable public {
        require(bytes(_id).length > 0, "id needs to be > 0");
        require(bytes(surveys[_id].id).length == 0, "survey already exists");
        require(_respondents > 0, "Need at least 1 respondent");
        require(msg.value >= _bounty, "Not enough funds sent for the bounty");

        Survey memory newSurvey = Survey(_id, msg.sender, _bounty, _bounty, _respondents, SurveyStatus.Open, block.timestamp, _timeLength*60, 0, 0, 0, new address[](0));
        surveys[_id]=newSurvey;

        emit SurveyCreated(msg.sender, _id);
    }

    function beginSurvey(string memory _id) public {
        require(surveys[_id].status == SurveyStatus.Open, "Survey is closed.");
        require(respondents[msg.sender][_id].respondentStartTime == 0, "Respondent already started");
        require(surveys[_id].respondentsCompleted < surveys[_id].respondents, "No more respondents allowed.");
        
        if((surveys[_id].respondentsCompleted + surveys[_id].respondentsStarted)==surveys[_id].respondents) {

            for (uint256 i = 0; i < surveys[_id].active.length; i++) {

                if ((respondents[surveys[_id].active[i]][_id].respondentStartTime + surveys[_id].timeLength) > block.timestamp) {
                    respondents[surveys[_id].active[i]][_id].status=RespondentStatus.Unfinished;
                    surveys[_id].active[i] = surveys[_id].active[surveys[_id].active.length - 1];
                    surveys[_id].active.pop();
                }
            }

            require((surveys[_id].respondentsCompleted + surveys[_id].respondentsStarted)<surveys[_id].respondents, "Survey full");

        }

        respondents[msg.sender][_id].respondentStartTime = block.timestamp;
        respondents[msg.sender][_id].status = RespondentStatus.Started;

        surveys[_id].respondentsStarted++;
        surveys[_id].active.push(msg.sender);

        emit SurveyStarted(msg.sender, _id);
    }

    function completeSurvey(string memory _id, string memory _answers) public {
        require(respondents[msg.sender][_id].status == RespondentStatus.Started, "Respondent didn't start survey");
        require(respondents[msg.sender][_id].status != RespondentStatus.Completed, "Respondent already completed survey");
        require((respondents[msg.sender][_id].respondentStartTime + surveys[_id].timeLength) > block.timestamp, "Respondent Exceeded Time limit"); 

        respondents[msg.sender][_id].status=RespondentStatus.Completed;
        respondents[msg.sender][_id].answers=_answers;
        respondents[msg.sender][_id].respondentCompleteTime=block.timestamp;

        surveys[_id].respondentsStarted--;
        surveys[_id].respondentsCompleted++;

        for (uint256 i = 0; i < surveys[_id].active.length; i++) {
            if (surveys[_id].active[i]==msg.sender){
                surveys[_id].active[i] = surveys[_id].active[surveys[_id].active.length - 1];
                surveys[_id].active.pop();  
            }
        }

        if (surveys[_id].respondentsCompleted == surveys[_id].respondents) {
            surveys[_id].status = SurveyStatus.Closed;
        }
        
        positiveAttestation(msg.sender);
        //if good credit, pay
        bool creditCheck = surveyCreditCheck(msg.sender);
        if (creditCheck) {
            respondents[msg.sender][_id].positive = true;
            if (surveys[_id].totalBounty>0) {
                awardEth(payable(msg.sender), _id);
            }
            respondents[msg.sender][_id].claimed = true;
        }

        emit SurveyCompleted(msg.sender, _id);
        
    }

    function closeSurvey(string memory _id) public {
        require(surveys[_id].status == SurveyStatus.Open, "Survey is already closed.");
        require(msg.sender == surveys[_id].creator, "Only survey creator can close");

        surveys[_id].status = SurveyStatus.Closed;
    }

    function positiveAttestation (address _respondent) internal {
        IAttestationStation attestStation = IAttestationStation(attestStationAddress);

        uint256 newValue;

        bytes memory attestation = attestStation.attestations(msg.sender, _respondent, bytes32("surveys.completed"));
        if (attestation.length == 0) {
            newValue = 1;
        } else {
            uint256 currentValue = abi.decode(attestation, (uint256));
            newValue = currentValue + 1;
        }
        
        IAttestationStation.AttestationData memory myAttestation = IAttestationStation.AttestationData({
            about: _respondent,
            key: bytes32("surveys.completed"),
            val: abi.encode(newValue)
        });

        IAttestationStation.AttestationData[] memory myAttestationArray = new IAttestationStation.AttestationData[](1);
        myAttestationArray[0] = myAttestation;
        attestStation.attest(myAttestationArray);

        emit AttestationSubmitted(bytes32("surveys.completed"), _respondent);
    }

    function negativeAttestation (string memory _id, address[] memory _respondents) public {
        require(msg.sender == surveys[_id].creator, "Only creator of survey can leave negative attestations");

        IAttestationStation attestStation = IAttestationStation(attestStationAddress);

        for (uint256 i = 0; i < _respondents.length; i++) {

            if(!respondents[_respondents[i]][_id].negative) {
                bytes memory attestation = attestStation.attestations(msg.sender, _respondents[i], bytes32("surveys.dq"));

                uint256 newValue;
                
                if (attestation.length == 0) {
                    newValue = 1;
                } else {
                    uint256 currentValue = abi.decode(attestation, (uint256));
                    newValue = currentValue + 1;
                }

                IAttestationStation.AttestationData memory myAttestation = IAttestationStation.AttestationData({
                    about: _respondents[i],
                    key: bytes32("surveys.dq"),
                    val: abi.encode(newValue)
                });

                IAttestationStation.AttestationData[] memory myAttestationArray = new IAttestationStation.AttestationData[](1);
                myAttestationArray[0] = myAttestation;
                attestStation.attest(myAttestationArray);
                respondents[msg.sender][_id].negative = true;
                emit AttestationSubmitted(bytes32("surveys.dq"), _respondents[i]);
            }
        }
    }

    function awardEth(address payable _to, string memory _id) internal {
        uint256 _amount = surveys[_id].totalBounty/surveys[_id].respondents;

        // Safely transfer the specified amount of ETH to the recipient
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Transfer failed");

        surveys[_id].remainingBounty -= _amount;
        surveys[_id].respondentsClaimed++;
        
        // Emit the TransferSuccessful event
        emit TransferSuccessful(_to, _amount);
    }

    function surveyCreditCheck(address _respondent) public view returns (bool) {
        IAttestationStation attestStation = IAttestationStation(attestStationAddress);

        bool pass;

        uint256 positiveScore;
        uint256 negativeScore;

        bytes memory positiveAttestationScore = attestStation.attestations(msg.sender, _respondent, bytes32("surveys.completed"));
        
        if (positiveAttestationScore.length > 0) {
             positiveScore = abi.decode(positiveAttestationScore, (uint256));
        }

        bytes memory negativeAttestationScore = attestStation.attestations(msg.sender, _respondent, bytes32("surveys.dq"));

        if (negativeAttestationScore.length > 0) {
             negativeScore = abi.decode(negativeAttestationScore, (uint256));
        }

        if (positiveScore >3) {
            if((10*negativeScore)<positiveScore) {
                pass = true;
            }
        }
        
        return pass;

    }

    function getPositiveAttestation(address _respondent) public view returns (bytes memory) {
        IAttestationStation attestStation = IAttestationStation(attestStationAddress);

        bytes memory positiveAttestationScore = attestStation.attestations(address(this), _respondent, bytes32("surveys.completed"));

        return positiveAttestationScore;
        //add logic to decode and get int

    }

    function getNegativeAttestation(address _respondent) public view returns (bytes memory) {
        IAttestationStation attestStation = IAttestationStation(attestStationAddress);

        bytes memory positiveAttestationScore = attestStation.attestations(address(this), _respondent, bytes32("surveys.dq"));

        return positiveAttestationScore;
        //add logic to decode and get int

    }


    function claimBounty(string memory _id) public {
        require(respondents[msg.sender][_id].status==RespondentStatus.Completed, "Respondent didn't complete survey");
        require(!respondents[msg.sender][_id].claimed, "Respondent already claimed");
        require((respondents[msg.sender][_id].respondentCompleteTime+daysInSeconds)>block.timestamp, "Respondent must wait 7 days");
        require(!respondents[msg.sender][_id].negative, "Respondent received a DQ for this survey");

        awardEth(payable(msg.sender), _id);
        positiveAttestation(msg.sender);
        respondents[msg.sender][_id].positive = true;
        respondents[msg.sender][_id].claimed = true;

    }

    function withdrawBounty(string memory _id) public {
        require(surveys[_id].status == SurveyStatus.Closed, "Survey must be closed.");
        require(msg.sender == surveys[_id].creator, "Only survey creator can close");
        require(surveys[_id].remainingBounty>0, "No remaining balance");

        if(surveys[_id].respondentsStarted>0) {

            for (uint256 i = 0; i < surveys[_id].active.length; i++) {

                if ((respondents[surveys[_id].active[i]][_id].respondentStartTime + surveys[_id].timeLength) > block.timestamp) {
                    respondents[surveys[_id].active[i]][_id].status=RespondentStatus.Unfinished;
                    surveys[_id].active[i] = surveys[_id].active[surveys[_id].active.length - 1];
                    surveys[_id].active.pop();
                    surveys[_id].respondentsStarted--;
                }
            }

            require(surveys[_id].respondentsStarted ==0, "Survey still has active respondents");

        }

        (bool success, ) = payable(msg.sender).call{value: surveys[_id].remainingBounty}("");
        require(success, "Transfer failed");

        surveys[_id].remainingBounty = 0;
    }
}
