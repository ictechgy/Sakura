// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// 메인 컨트랙트 선언
contract Sakura is ERC20, Ownable {
    // 메인컨트랙트는 서브 컨트랙트를 소유
    mapping(uint => address) leafMap;
    uint leafID = 0;
    uint maxSurveysPerLeaf = 50;

    constructor() ERC20("Sakura", "SKURA") {
        _mint(msg.sender, 100000000000);
    }

    // 새로운 서브 컨트랙트를 생성
    function createLeafContract() public onlyOwner {
        require(leafMap[leafID] == address(0), "leaf aleady created");
        Leaf leaf = new Leaf();
        leafMap[leafID] = address(leaf);
        leafID++;
    }

    // 설문조사 생성 요청
    function createSurvey(string memory _question, string[] memory _options) public onlyOwner {
        uint latestLeafIndex = leafID - 1;
        require(leafMap[latestLeafIndex] != address(0), "lastest leaf does not exist");
        
        Leaf leaf = Leaf(leafMap[leafID]);
        leaf.createSurvey(_question, _options);
    }

    // TODO: 특정 설문조사 삭제 및 CRUD 필요
}

// 하위 컨트랙트
contract Leaf is Ownable {
    struct Survey {
        string question;
        string[] options;
        uint[] voteCountPerOptions;
        bool isActive;
    }

    Survey[] surveys;

    // 설문조사 생성
    function createSurvey(string memory _question, string[] memory _options, bool _initialActiveState) public onlyOwner {
        require(_options.length >= 2, "At least 2 options are required");
        uint[] memory initialVotes = new uint[](_options.length);
        surveys.push(
            Survey(
                {
                    question: _question,
                    options: _options,
                    votes: initialVotes,
                    active: _initialActiveState
                }
            )
        );
    }

    // 투표 함수
    function vote(uint _surveyId, uint _optionIndex) public {
        require(_surveyId < surveys.length, "Survey does not exist");
        require(surveys[_surveyId].active, "Survey is not active");
        require(_optionIndex < surveys[_surveyId].options.length, "Invalid option index");
        surveys[_surveyId].votes[_optionIndex]++;
        // TODO: 사용자 체크 필요. msg.sender
    }

    // 설문조사 결과 보기
    function getSurveyResults(uint _surveyId) public view returns (string memory, string[] memory, uint[] memory, bool) {
        require(_surveyId < surveys.length, "Survey does not exist");
        Survey memory survey = surveys[_surveyId];

        return (survey.question, survey.options, survey.voteCountPerOptions, survey.isActive)
    }
}