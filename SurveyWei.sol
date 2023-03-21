pragma solidity ^0.8.0;

//import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IAttestationStation {
    struct AttestationData {
        address about;
        bytes32 key;
        bytes val;
    }

    function attest(AttestationData[] memory _attestations) external;

    function getAttestation(address _attester, address _subject, bytes32 _key) external view returns (bytes memory);
}

contract SurveyWei {

    //using SafeMath for uint256;

    address attestStationAddress = 0xEE36eaaD94d1Cc1d0eccaDb55C38bFfB6Be06C77;

    uint256 minAttestations = 3;

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

    function createSurvey(string memory _id, uint256 _bounty, uint256 _respondents, uint256 _timeLength) public {
        Survey memory newSurvey = Survey(_id, msg.sender, _bounty, _bounty, _respondents, SurveyStatus.Open, block.timestamp, _timeLength, 0, 0, new address[](0));
        surveys[_id]=newSurvey;

        emit SurveyCreated(msg.sender, _id);
    }

    function beginSurvey(string memory _id) public {
        require(surveys[_id].status == SurveyStatus.Open, "Survey is closed.");

        if(surveys[_id].respondents>0) {
            require(surveys[_id].respondentsCompleted < surveys[_id].respondents, "No more respondents allowed.");
            
            if((surveys[_id].respondentsCompleted + surveys[_id].respondentsStarted)==surveys[_id].respondents) {

                for (uint256 i = 0; i < surveys[_id].active.length; i++) {

                    if ((respondents[surveys[_id].active[i]][_id].respondentStartTime + surveys[_id].timeLength) > block.timestamp) {
                        respondents[surveys[_id].active[i]][_id].status=RespondentStatus.Unfinished;
                        surveys[_id].active[i] = surveys[_id].active[surveys[_id].active.length - 1];
                        surveys[_id].active.pop();
                    }
                }
            }
        }

        respondents[msg.sender][_id].respondentStartTime = block.timestamp;
        respondents[msg.sender][_id].status = RespondentStatus.Started;

        surveys[_id].respondentsStarted++;
        surveys[_id].active.push(msg.sender);
    }

    function completeSurvey(string memory _id, string memory _answers) public {
        require(respondents[msg.sender][_id].status == RespondentStatus.Started, "Respondent didn't start survey");
        require(respondents[msg.sender][_id].status != RespondentStatus.Completed, "Respondent already completed survey");
        require((respondents[msg.sender][_id].respondentStartTime + surveys[_id].timeLength) > block.timestamp, "Respondent Exceeded Time limit"); 

        respondents[msg.sender][_id].status=RespondentStatus.Completed;
        respondents[msg.sender][_id].answers=_answers;

        surveys[_id].respondentsStarted--;
        surveys[_id].respondentsCompleted++;

        positiveAttestation(msg.sender);
        respondents[msg.sender][_id].positive = true;

        for (uint256 i = 0; i < surveys[_id].active.length; i++) {
            if (surveys[_id].active[i]==msg.sender){
                surveys[_id].active[i] = surveys[_id].active[surveys[_id].active.length - 1];
                surveys[_id].active.pop();  
            }
        }

        if (surveys[_id].respondents>0) {
            if (surveys[_id].respondentsCompleted == surveys[_id].respondents) {
                surveys[_id].status = SurveyStatus.Closed;
            }
        }

    }

    function closeSurvey(string memory _id) public {
        require(surveys[_id].status == SurveyStatus.Open, "Survey is closed.");
        require(msg.sender == surveys[_id].creator, "Only survey creator can close");
        //close survey. if users have started, let them completed. don't let anyone else start.

        surveys[_id].status = SurveyStatus.Closed;

    }

    function positiveAttestation (address _respondent) internal {
        IAttestationStation attestStation = IAttestationStation(attestStationAddress);

        uint256 newValue;

        bytes memory attestation = attestStation.getAttestation(msg.sender, _respondent, bytes32("surveys.completed"));
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
    }

    function negativeAttestation (string memory _id, address[] memory _respondents) public {
        require(msg.sender == surveys[_id].creator, "Only creator of survey can leave negative attestations");

        IAttestationStation attestStation = IAttestationStation(attestStationAddress);

        for (uint256 i = 0; i < _respondents.length; i++) {

            if(!respondents[_respondents[i]][_id].negative) {
                bytes memory attestation = attestStation.getAttestation(msg.sender, i, bytes32("surveys.dq"));

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
            }
        }
    }

    
    function withdrawBounty() public {}

    function claimBounty() public {}

}
