// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Capped } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// 메인 컨트랙트 선언
contract Soboro is ERC20, ERC20Capped, ERC20Burnable, Ownable {
    // 메인컨트랙트는 서브 컨트랙트를 소유
    // TODO: 접근제어 수정 
    uint256 private constant MAX_SUPPLY = 10**11;
    mapping(uint => address) private crumbMap;
    uint private crumbGenID = 0;
    uint private maxSurveysPerCrumb = 50; // TODO: 조정 가능하게

    constructor() ERC20("Soboro", "SBR") ERC20Capped(MAX_SUPPLY) Ownable(msg.sender) {
        _mint(msg.sender, 10**5);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }

    // 새로운 서브 컨트랙트를 생성
    function createCrumbContract() public onlyOwner {
        require(crumbMap[crumbGenID] == address(0), "crumb aleady baked");
        Crumb crumb = new Crumb();
        crumbMap[crumbGenID] = address(crumb);
        crumbGenID++;
    }

    // 설문조사 생성 요청
    function requestSurveyCreation(string memory _question, string[] memory _options, bool _initialActiveState) public onlyOwner {
        uint latestCrumbIndex = crumbGenID - 1;
        require(crumbMap[latestCrumbIndex] != address(0), "lastest crumb does not exist. Who ate it?");
        
        Crumb crumb = Crumb(crumbMap[latestCrumbIndex]);
        uint countOfSurvey = crumb.getSurveyCount();

        if (countOfSurvey < maxSurveysPerCrumb) {
            crumb.createSurvey(_question, _options, _initialActiveState);
        } else {
            revert("max survey count per crumb reached. create Crumb first");
        }
    }

    // 활성화상태 변경
    function changeActiveStatus(uint crumbID, uint surveyIndex, bool isActive) public onlyOwner {
        require(crumbID >= 0 && surveyIndex >= 0, "invalid ID/Index");
        require(crumbMap[crumbID] != address(0), "crumb not exists");
        
        Crumb crumb = Crumb(crumbMap[crumbID]);

        require(surveyIndex < crumb.getSurveyCount() , "survey does not exist");

        (, bool isSurveyActive) = crumb.surveys(surveyIndex);
        require(isSurveyActive != isActive , "survey is already in the desired active state");
        
        crumb.changeActiveStatus(surveyIndex, isActive);
    }
    // TODO: 특정 설문조사 삭제 및 CRUD 필요

    function getCrumbCount() public view returns (uint) {
        return crumbGenID;
    }

    function getCrumb(uint index) public view returns (Crumb) {
        require(index >= 0 && index < crumbGenID, "invalid index");

        return Crumb(crumbMap[index]);
    }
}

// 하위 컨트랙트
contract Crumb {
    struct Survey {
        string question;
        string[] options;
        uint[] voteCountPerOptions;
        bool isActive;
        mapping(address => bool) hasVoted;
    }

    Survey[] public surveys;

    // 설문조사 생성
    function createSurvey(string memory _question, string[] memory _options, bool _initialActiveState) public {
        require(_options.length >= 2, "At least 2 options are required");
        
        surveys.push();

        Survey storage survey = surveys[surveys.length - 1];
        uint[] memory initialVotes = new uint[](_options.length);
        survey.question = _question;
        survey.options = _options;
        survey.voteCountPerOptions = initialVotes;
        survey.isActive = _initialActiveState;

    }

    // 투표 함수
    function vote(uint _surveyId, uint _optionIndex) public {
        require(_surveyId < surveys.length, "Survey does not exist");
        require(surveys[_surveyId].isActive, "Survey is not active");
        require(_optionIndex < surveys[_surveyId].options.length, "Invalid option index");
        require(surveys[_surveyId].hasVoted[msg.sender] == false, "User has already voted");

        surveys[_surveyId].voteCountPerOptions[_optionIndex]++;
        surveys[_surveyId].hasVoted[msg.sender] = true;
    }

    // 활성화 상태 변경
    function changeActiveStatus(uint surveyIndex, bool isActive) public {
        require(surveys[surveyIndex].isActive != isActive , "survey is already in the desired active state");
        
        surveys[surveyIndex].isActive = isActive;
    }
    
    // 설문 갯수 반환
    function getSurveyCount() public view returns (uint256) {
        return surveys.length;
    }
}