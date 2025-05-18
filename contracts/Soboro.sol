// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "./Crumb.sol";

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
        __ReentrancyGuardTransient_init();

        _mint(msg.sender, 10**6);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable, ERC20CappedUpgradeable) {
        super._update(from, to, value);
    }

    // 새로운 서브 컨트랙트를 생성
    function createCrumbContract() public onlyOwner {
        require(crumbMap[crumbGenID] == address(0)); // crumb aleady baked
        Crumb crumb = new Crumb();
        crumbMap[crumbGenID] = address(crumb);
        crumbGenID++;
    }

    // ID 정정
    function correctCrumbGenID(uint newID) public onlyOwner {
        require(newID >= 0 && newID <= type(uint256).max && crumbMap[newID] == address(0)); // invalid new ID

        crumbGenID = newID;
    }

    // TODO: 설문 제안 시 토큰 소모 / 어떤 사람이 Proposal이 될 것인지, 어떤 설문이 뽑힐 것인지 결정하는 방식 필요
    // 설문조사 생성 요청
    // 🔥 TODO for security vulnerabilities: _question에 calldata? / bool값 true || false 검증 필요? 
    function requestSurveyCreation(string memory _question, string[] memory _options, bool _initialActiveState) public onlyOwner nonReentrant {
        require(bytes(_question).length != 0); // empty question is not allowed
        require(_options.length >= 2); // At least 2 options are required

        uint latestCrumbIndex = crumbGenID - 1;
        require(crumbMap[latestCrumbIndex] != address(0)); // lastest crumb does not exist. Who ate it?
        
        Crumb crumb = Crumb(crumbMap[latestCrumbIndex]);
        uint countOfSurvey = crumb.getSurveyCount();

        if (countOfSurvey < maxSurveysPerCrumb) {
            crumb.createSurvey(_question, _options, _initialActiveState);
        } else {
            revert(); // 크게 revert 할 내용 없음 - max survey count per crumb reached. create Crumb first
        }
    }

    // TODO: - 보상 생태계(활성화 상태 변경했을 때 또는 투표 종료 시 - batch)
    // 활성화상태 변경
    function changeActiveStatus(uint crumbID, uint surveyIndex, bool isActive) public onlyOwner {
        require(crumbID >= 0 && crumbID <= type(uint256).max && surveyIndex >= 0 && surveyIndex <= type(uint256).max, "invalid ID/Index");
        require(crumbMap[crumbID] != address(0)); // crumb not exists
        
        Crumb crumb = Crumb(crumbMap[crumbID]);

        require(surveyIndex < crumb.getSurveyCount()); // survey does not exist

        (, bool isSurveyActive) = crumb.surveys(surveyIndex);
        require(isSurveyActive != isActive); // survey is already in the desired active state
        
        crumb.changeActiveStatus(surveyIndex, isActive);
    }

    // 특정 설문에 참여
    function vote(uint crumbID, uint surveyIndex, uint optionIndex) public nonReentrant {
        require(msg.sender != address(0)); // invalid address
        require(crumbID >= 0 && crumbID <= type(uint256).max && surveyIndex >= 0 && surveyIndex <= type(uint256).max && optionIndex >= 0 && optionIndex <= type(uint256).max && crumbID < crumbGenID, "invalid vote request");
        
        Crumb crumb = Crumb(crumbMap[crumbID]);

        require(surveyIndex < crumb.getSurveyCount()); // survey does not exist

        (, bool isSurveyActive) = crumb.surveys(surveyIndex);
        require(isSurveyActive == true); // survey is not activated
        require(crumb.amIVoted(surveyIndex) == false); // aleady voted

        crumb.vote(surveyIndex, optionIndex);
    }

    // Crumb 갯수 반환
    function getCrumbCount() public view returns (uint) {
        return crumbGenID;
    }

    // 특정 index Crumb 반환
    function getCrumb(uint index) public view returns (Crumb) {
        require(index >= 0 && index <= type(uint256).max && index < crumbGenID); // invalid index
        require(crumbMap[index] != address(0)); // crumb not exists

        return Crumb(crumbMap[index]);
    }

    // maxCount 조정
    function setMaxSurveyCount(uint newMaxSurveyCount) public onlyOwner {
        require(newMaxSurveyCount >= 1 && maxSurveysPerCrumb <= type(uint256).max); // invalid count
        
        maxSurveysPerCrumb = newMaxSurveyCount;
    }

    // TODO: Proxy 패턴 또는 CrumbManager (로직 분리)
}