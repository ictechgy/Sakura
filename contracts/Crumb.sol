// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

// 하위 컨트랙트
contract Crumb is Initializable, OwnableUpgradeable, ReentrancyGuardTransientUpgradeable {
    struct Survey {
        string question;
        string[] options;
        uint[] voteCountPerOptions; // TODO: - event로 슬롯 효율화 가능, overflow 방지(SafeMath)
        bool isActive;
        mapping(address => bool) hasVoted; // TODO: - 유저 한명당 1bit로 하여 인덱싱한 뒤 효율화 / 또는 event log로 외부에서 필터링? 
    }

    Survey[] public surveys;
    event Voted(address indexed voter, uint indexed surveyIndex, uint indexed optionIndex);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuardTransient_init();
    }

    // 설문조사 생성
    function createSurvey(string calldata _question, string[] memory _options, bool _initialActiveState) public onlyOwner {
        require(bytes(_question).length != 0, "empty question is not allowed");
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
    function vote(uint _surveyID, uint _optionIndex) public nonReentrant {
        require(msg.sender != address(0), "invalid request");
        require(_surveyID >= 0 && _surveyID <= type(uint256).max && _surveyID < surveys.length, "invalid id");
        require(surveys[_surveyID].isActive, "Survey is not active");
        require(_optionIndex >= 0 && _optionIndex < surveys[_surveyID].options.length, "Invalid option index");
        require(surveys[_surveyID].hasVoted[msg.sender] == false, "User has already voted");
        
        require(surveys[_surveyID].voteCountPerOptions[_optionIndex] <= type(uint256).max, "optionIndex reached max");

        surveys[_surveyID].hasVoted[msg.sender] = true;
        surveys[_surveyID].voteCountPerOptions[_optionIndex]++;

        emit Voted(msg.sender, _surveyID, _optionIndex);
    }

    // 활성화 상태 변경
    function changeActiveStatus(uint surveyIndex, bool isActive) public onlyOwner {
        require(surveyIndex >= 0 && surveyIndex < surveys.length && surveyIndex <= type(uint256).max, "invalid index");
        require(surveys[surveyIndex].isActive != isActive , "survey is already in the desired active state");
        
        surveys[surveyIndex].isActive = isActive;
    }
    
    // 설문 갯수 반환
    function getSurveyCount() public view returns (uint256) {
        return surveys.length;
    }

    // 내가 특정 설문에 참여했는지 확인 (msg.sender)
    function amIVoted(uint surveyID) public view returns (bool) {
        require(surveyID >= 0 && surveyID <= type(uint256).max && surveyID < surveys.length, "invalid id");
        return hasVoted(msg.sender, surveyID);
    }

    // 누군가가 특정 설문에 참여했는지 확인
    function hasVoted(address voterAddress, uint surveyID) public view returns (bool) {
        require(voterAddress != address(0), "invalid address");
        require(surveyID >= 0 && surveyID < surveys.length && surveyID <= type(uint256).max, "invalid survey ID");

        return surveys[surveyID].hasVoted[voterAddress];
    }

    // 특정 index Survey의 부가정보(선택지) 조회 (자동 getter에서 돌려주지 않는)
    function getSurveyOptions(uint surveyIndex) public view returns (string[] memory) {
        require(surveyIndex >= 0 && surveyIndex < surveys.length && surveyIndex <= type(uint256).max, "invalid index");
        
        string[] memory options = surveys[surveyIndex].options; // TODO: 캐스팅 명시화 필요한지 확인
        return options;
    }

    // 특정 index Survey의 부가정보(항목별 투표 수) 조회 (자동 getter에서 돌려주지 않는)
    function getSurveyVoteCountPerOptions(uint surveyIndex) public view returns (uint256[] memory) {
        require(surveyIndex >= 0 && surveyIndex < surveys.length && surveyIndex <= type(uint256).max, "invalid index");
        
        return surveys[surveyIndex].voteCountPerOptions;
    }
}