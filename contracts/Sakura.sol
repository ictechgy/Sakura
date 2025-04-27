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

    // 특정 설문조사 삭제 및 CRUD 필요
}

