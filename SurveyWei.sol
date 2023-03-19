pragma solidity ^0.8.0;

contract SurveyWei {
    enum SurveyStatus { Open, Closed }
    enum RespondnetStatus { Started, Finished, Cancelled, DQ}

    struct Survey {
        string id;
        address creator;
        uint256 bounty;
        uint256 respondents;
        SurveyStatus status;
        uint256 createdAt;
        uint256 timeLength;
        uint256 respondentsStarted;
        uint256 respondentsFinished;
        address[] active;
    }

    struct Respondent {
        uint256 respondentStartTime;
        uint256 respondentFinishTime;
        RespondnetStatus status;
        bool claimed;
    }

    mapping(string => Survey) public surveys;

    mapping(address => mapping(string => Respondent)) public respondents;

    event SurveyCreated(address indexed creator, string id);

    function createSurvey(string memory _id, uint256 _bounty, uint256 _respondents, uint256 _timeLength) public {
        Survey memory newSurvey = Survey(_id, msg.sender, _bounty, _respondents, SurveyStatus.Open, block.timestamp, _timeLength, 0, 0, new address[](0));
        surveys[_id]=newSurvey;

        emit SurveyCreated(msg.sender, _id);
    }

    function beginSurvey(string memory _id) public {
        require(surveys[_id].status == SurveyStatus.Open, "Survey is closed.");
        require(surveys[_id].respondentsFinished < surveys[_id].respondents, "No more respondents allowed.");

        if((surveys[_id].respondentsFinished + surveys[_id].respondentsStarted)==surveys[_id].respondents) {

            for (uint256 i = 0; i < surveys[_id].active.length; i++) {

                if ((respondents[surveys[_id].active[i]][_id].respondentStartTime + surveys[_id].timeLength) > block.timestamp) {
                    respondents[surveys[_id].active[i]][_id].status=RespondnetStatus.Cancelled;
                    surveys[_id].active[i] = surveys[_id].active[surveys[_id].active.length - 1];
                    surveys[_id].active.pop();
                }
            }
        }

        respondents[msg.sender][_id].respondentStartTime = block.timestamp;
        respondents[msg.sender][_id].status = RespondnetStatus.Started;

        surveys[_id].respondentsStarted++;
        surveys[_id].active.push(msg.sender);

    }

    function finishSurvey(string memory _id) public {
        require(respondents[msg.sender][_id].status == RespondnetStatus.Started, "Respondent didn't start survey");
        require((respondents[msg.sender][_id].respondentStartTime + surveys[_id].timeLength) > block.timestamp, "Respondent Exceeded Time limit"); 
        //can maybe update ^^ so another slot opens

        respondents[msg.sender][_id].status=RespondnetStatus.Finished;
        surveys[_id].respondentsStarted--;
        surveys[_id].respondentsFinished++;

        for (uint256 i = 0; i < surveys[_id].active.length; i++) {
            if (surveys[_id].active[i]==msg.sender){
                surveys[_id].active[i] = surveys[_id].active[surveys[_id].active.length - 1];
                surveys[_id].active.pop();  
        }
        }

        if (surveys[_id].respondentsFinished == surveys[_id].respondents) {
            surveys[_id].status = SurveyStatus.Closed;
        }

    }

    function closeSurvey(string memory _id) public {
        require(surveys[_id].status == SurveyStatus.Open, "Survey is closed.");
        //close survey. if users have started, let them finish. don't let anyone else start.


    }
}
