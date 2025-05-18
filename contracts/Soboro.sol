// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

// 메인 컨트랙트 선언
contract Soboro is Initializable, ERC20Upgradeable, ERC20CappedUpgradeable, ERC20BurnableUpgradeable, OwnableUpgradeable, ReentrancyGuardTransientUpgradeable {
    uint256 private constant MAX_SUPPLY = 10**11;

    // 메인컨트랙트는 서브 컨트랙트를 소유
    mapping(uint => address) private crumbMap;
    uint private crumbGenID = 0;
    uint private maxSurveysPerCrumb = 50;

    function initialize() public initializer {
        __ERC20_init("Soboro", "SBR"); 
        __ERC20Capped_init(MAX_SUPPLY);
        __ERC20Burnable_init();
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        _mint(msg.sender, 10**6);
    }

    // 새로운 서브 컨트랙트를 생성
    function createCrumbContract() public onlyOwner {
        require(crumbMap[crumbGenID] == address(0), "crumb aleady baked");
        Crumb crumb = new Crumb();
        crumbMap[crumbGenID] = address(crumb);
        crumbGenID++;
    }

    // ID 정정
    function correctCrumbGenID(uint newID) public onlyOwner {
        require(newID >= 0 && crumbMap[newID] == address(0), "invalid new ID");

        crumbGenID = newID;
    }

    // TODO: 설문 제안 시 토큰 소모 / 어떤 사람이 Proposal이 될 것인지, 어떤 설문이 뽑힐 것인지 결정하는 방식 필요
    // 설문조사 생성 요청
    function requestSurveyCreation(string memory _question, string[] memory _options, bool _initialActiveState) public onlyOwner nonReentrant {
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

    // TODO: - 보상 생태계(활성화 상태 변경했을 때 또는 투표 종료 시 - batch)
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

    // 특정 설문에 참여
    function vote(uint crumbID, uint surveyIndex, uint optionIndex) public {
        require(msg.sender != address(0), "invalid address");
        require(crumbID >= 0 && surveyIndex >= 0 && optionIndex >= 0 && crumbID < crumbGenID, "invalid vote request");
        
        Crumb crumb = Crumb(crumbMap[crumbID]);

        require(surveyIndex < crumb.getSurveyCount() , "survey does not exist");

        (, bool isSurveyActive) = crumb.surveys(surveyIndex);
        require(isSurveyActive == true, "survey is not activated");
        require(crumb.amIVoted(surveyIndex) == false, "aleady voted");

        crumb.vote(surveyIndex, optionIndex);
    }

    // Crumb 갯수 반환
    function getCrumbCount() public view returns (uint) {
        return crumbGenID;
    }

    // 특정 index Crumb 반환
    function getCrumb(uint index) public view returns (Crumb) {
        require(index >= 0 && index < crumbGenID, "invalid index");
        require(crumbMap[index] != address(0), "crumb not exists");

        return Crumb(crumbMap[index]);
    }

    // maxCount 조정
    function setMaxSurveyCount(uint newMaxSurveyCount) public onlyOwner {
        require(newMaxSurveyCount >= 1, "invalid count");
        
        maxSurveysPerCrumb = newMaxSurveyCount;
    }

    // TODO: Proxy 패턴 또는 CrumbManager (로직 분리)
}

// 하위 컨트랙트
contract Crumb is Initializable, OwnableUpgradeable {
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
        __ReentrancyGuard_init();

        _mint(msg.sender, 10**6);
    }

    // 설문조사 생성
    function createSurvey(string memory _question, string[] memory _options, bool _initialActiveState) public onlyOwner {
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
    function vote(uint _surveyID, uint _optionIndex) public { // TODO: nonReentrant 고려
        require(msg.sender != address(0), "invalid request");
        require(_surveyID >= 0 && _surveyID < surveys.length, "invalid id");
        require(surveys[_surveyID].isActive, "Survey is not active");
        require(_optionIndex < surveys[_surveyID].options.length, "Invalid option index");
        require(surveys[_surveyID].hasVoted[msg.sender] == false, "User has already voted");

        surveys[_surveyID].hasVoted[msg.sender] = true;
        surveys[_surveyID].voteCountPerOptions[_optionIndex]++;

        emit Voted(msg.sender, _surveyID, _optionIndex);
    }

    // 활성화 상태 변경
    function changeActiveStatus(uint surveyIndex, bool isActive) public onlyOwner {
        require(surveyIndex >= 0 && surveyIndex < surveys.length, "invalid index");
        require(surveys[surveyIndex].isActive != isActive , "survey is already in the desired active state");
        
        surveys[surveyIndex].isActive = isActive;
    }
    
    // 설문 갯수 반환
    function getSurveyCount() public view returns (uint256) {
        return surveys.length;
    }

    // 내가 특정 설문에 참여했는지 확인 (msg.sender)
    function amIVoted(uint surveyID) public view returns (bool) {
        hasVoted(msg.sender, surveyID);
    }

    // 누군가가 특정 설문에 참여했는지 확인
    function hasVoted(address voterAddress, uint surveyID) public view returns (bool) {
        require(voterAddress != address(0), "invalid address");
        require(surveyID >= 0 && surveyID < surveys.length, "invalid survey ID");

        return surveys[surveyID].hasVoted[voterAddress];
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