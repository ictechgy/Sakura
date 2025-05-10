// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Capped } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// 메인 컨트랙트 선언
contract Soboro is ERC20, ERC20Capped, ERC20Burnable, AccessControl {
    bytes32 private constant BAKER_ROLE = keccak256("BAKER_ROLE");
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 private constant PROPOSAL_ROLE = keccak256("PROPOSAL_ROLE");
    uint256 private constant MAX_SUPPLY = 10**11;

    // 메인컨트랙트는 서브 컨트랙트를 소유
    mapping(uint => address) private crumbMap;
    uint private crumbGenID = 0;
    uint private maxSurveysPerCrumb = 50;
    // TODO: - Access Control에 Proposal 역할 및 설문 제안에 따른 reward? / 어떤 사람이 Proposal이 될 것인지, 어떤 설문이 뽑힐 것인지 결정하는 방식 필요

    constructor() ERC20("Soboro", "SBR") ERC20Capped(MAX_SUPPLY) {
        _mint(msg.sender, 10**5);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }

    // 새로운 서브 컨트랙트를 생성
    function createCrumbContract() public onlyRole(BAKER_ROLE) {
        require(crumbMap[crumbGenID] == address(0), "crumb aleady baked");
        Crumb crumb = new Crumb();
        crumbMap[crumbGenID] = address(crumb);
        crumbGenID++;
    }

    // ID 정정
    function correctCrumbGenID(uint newID) public onlyRole(BAKER_ROLE) {
        require(newID >= 0 && crumbMap[newID] == address(0), "invalid new ID");

        crumbGenID = newID;
    }

    // 설문조사 생성 요청
    function requestSurveyCreation(string memory _question, string[] memory _options, bool _initialActiveState) public onlyRole(PROPOSAL_ROLE) {
        require(bytes(_question).length != 0, "empty question is not allowed");
        require(_options.length >= 2, "At least 2 options are required");

        uint latestCrumbIndex = crumbGenID - 1;
        require(crumbMap[latestCrumbIndex] != address(0), "lastest crumb does not exist. Who ate it?");
        
        Crumb crumb = Crumb(crumbMap[latestCrumbIndex]);
        uint countOfSurvey = crumb.getSurveyCount();

        if (countOfSurvey < maxSurveysPerCrumb) {
            crumb.createSurvey(_question, _options, _initialActiveState);
        } else {
            revert("max survey count per crumb reached. create Crumb first"); // 크게 revert 할 내용 없음
        }
    }

    // TODO: - 활성화 상태 변경 또는 투표 종료 시 보상 생태계 
    // 활성화상태 변경
    function changeActiveStatus(uint crumbID, uint surveyIndex, bool isActive) public onlyRole(PROPOSAL_ROLE) {
        require(crumbID >= 0 && surveyIndex >= 0, "invalid ID/Index");
        require(crumbMap[crumbID] != address(0), "crumb not exists");
        
        Crumb crumb = Crumb(crumbMap[crumbID]);

        require(surveyIndex < crumb.getSurveyCount() , "survey does not exist");

        (, bool isSurveyActive) = crumb.surveys(surveyIndex);
        require(isSurveyActive != isActive , "survey is already in the desired active state");
        
        crumb.changeActiveStatus(surveyIndex, isActive);
    }

    // 특정 설문에 참여
    function vote(uint crumbID, uint surveyIndex, uint optionIndex) public {
        require(crumbID >= 0 && surveyIndex >= 0 && optionIndex >= 0 && crumbID < crumbGenID, "invalid vote request");
        
        Crumb crumb = Crumb(crumbMap[crumbID]);

        require(surveyIndex < crumb.getSurveyCount() , "survey does not exist");

        (, bool isSurveyActive) = crumb.surveys(surveyIndex);
        require(isSurveyActive == true, "survey is not activated");
        require(crumb.hasVoted(surveyIndex) == false, "aleady voted");

        crumb.vote(surveyIndex, optionIndex);
    }

    // Crumb 갯수 반환
    function getCrumbCount() public view returns (uint) {
        return crumbGenID;
    }

    // 특정 index Crumb 반환
    function getCrumb(uint index) public view returns (Crumb) {
        require(index >= 0 && index < crumbGenID, "invalid index");

        return Crumb(crumbMap[index]);
    }

    // maxCount 조정
    function setMaxSurveyCount(uint newMaxSurveyCount) public onlyRole(BAKER_ROLE) {
        require(newMaxSurveyCount >= 1, "invalid count");
        
        maxSurveysPerCrumb = newMaxSurveyCount;
    }

    // TODO: Proxy 패턴 또는 CrumbManager
}

// 하위 컨트랙트
contract Crumb is Ownable {
    struct Survey {
        string question;
        string[] options;
        uint[] voteCountPerOptions; // TODO: - event로 슬롯 효율화 가능 
        bool isActive;
        mapping(address => bool) hasVoted; // TODO: - 유저 한명당 1bit로 하여 인덱싱한 뒤 효율화 
    }

    Survey[] public surveys;
    event Voted(address indexed voter, uint surveyIndex, uint optionIndex);

    constructor() Ownable(msg.sender) { }

    // 설문조사 생성
    function createSurvey(string memory _question, string[] memory _options, bool _initialActiveState) public onlyOwner {
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
    function changeActiveStatus(uint surveyIndex, bool isActive) public onlyOwner {
        require(surveys[surveyIndex].isActive != isActive , "survey is already in the desired active state");
        
        surveys[surveyIndex].isActive = isActive;
    }
    
    // 설문 갯수 반환
    function getSurveyCount() public view returns (uint256) {
        return surveys.length;
    }

    // msg.sender가 특정 설문에 참여했는지 확인
    function hasVoted(uint surveyID) public view returns (bool) {
        require(surveyID < surveys.length, "invalid survey ID");

        return surveys[surveyID].hasVoted[msg.sender];
    }

    // 특정 index Survey의 부가정보(선택지) 조회 (자동 getter에서 돌려주지 않는)
    function getSurveyOptions(uint surveyIndex) public view returns (string[] memory) {
        require(surveyIndex >= 0 && surveyIndex < surveys.length, "invalid index");
        
        string[] memory options = surveys[surveyIndex].options; // TODO: 캐스팅 명시화 필요한지 확인
        return options;
    }

    // 특정 index Survey의 부가정보(항목별 투표 수) 조회 (자동 getter에서 돌려주지 않는)
    function getSurveyVoteCountPerOptions(uint surveyIndex) public view returns (uint256[] memory) {
        require(surveyIndex >= 0 && surveyIndex < surveys.length , "invalid index");
        
        return surveys[surveyIndex].voteCountPerOptions;
    }
}