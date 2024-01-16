// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "erc721a/contracts/ERC721A.sol";
// import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "@layerzerolabs/solidity-examples/contracts/token/onft721/ONFT721Core.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./ISRCNFT.sol";

contract SpaceshipT1 is
    ONFT721Core,
    ERC721A,
    ERC721A__IERC721Receiver,
    ISRCNFT
{
    // Whether this contract is mintable.
    bool public mintable;

    // The address of the cosigner server.
    address public cosigner;

    address public beneficiary;

    // Current base URI.
    string public currentBaseURI;

    // The suffix for the token URL, e.g. ".json".
    string public tokenURISuffix;

    uint256 private constant _One_HOUR = 1 hours;
    uint256 private constant _One_DAY = 1 days;
    uint256 private constant one_minute = 1 minutes;
    uint256 public expireTime;

    // Mint stage infomation. See MintStageInfo for details.
    MintStageInfo[] public mintStages;

    // Minted count per stage.
    mapping(uint256 => uint256) public stageMintedCounts;

    // Minted tokenID stakeDays.
    mapping(uint256 => uint256) public tokenIdStakeDays;
    mapping(string => bool) private ridvalue;
    uint256 public maxSupply;
    error notSatifiedSig();

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _tokenURISuffix,
        string memory _currentBaseURI,
        address _cosigner,
        address _beneficiary,
        uint256 _minGasToTransferAndStore,
        address _lzEndpoint,
        uint32 _expire,
        uint256 _maxSupply
    )
        payable
        ERC721A(_name, _symbol)
        ONFT721Core(_minGasToTransferAndStore, _lzEndpoint)
        Ownable(msg.sender)
    {
        mintable = true;
        tokenURISuffix = _tokenURISuffix;
        currentBaseURI = _currentBaseURI;
        cosigner = _cosigner; // ethers.constants.AddressZero for no cosigning
        beneficiary = _beneficiary;
        expireTime = _expire * one_minute;
        maxSupply = _maxSupply;
    }

    /**
     * @dev Sets mintable.
     */
    function setMintable(bool _mintable) external onlyOwner {
        mintable = _mintable;
    }

    function updateExpire(uint32 _expire) external onlyOwner {
        expireTime = _expire * one_minute;
    }

    /**
     * @dev Sets cosigner.
     */
    function updateCosigner(address _cosigner) external onlyOwner {
        cosigner = _cosigner;
    }

    /**
     * @dev Sets stages in the format of an array of `MintStageInfo`.
     */
    function setStages(InputMintStageInfo[] calldata newStages)
        external
        onlyOwner
    {
        uint256 newSize = newStages.length;
        require((newSize != 0), "NO_STAGE");
        uint256 originalSize = mintStages.length;
        for (uint256 i = 0; i < originalSize; i++) {
            mintStages.pop();
        }

        for (uint256 i = 0; i < newStages.length; i++) {
            if (i >= 1) {
                _assertValidStartAndEndTimestamp(
                    newStages[i].startTimeUnixSeconds,
                    mintStages[i - 1].endTimeUnixSeconds
                );
            }
            mintStages.push(
                MintStageInfo({
                    whiteSalePrice: newStages[i].whiteSalePrice,
                    publicSalePrice: newStages[i].publicSalePrice,
                    maxStageSupply: newStages[i].maxStageSupply,
                    whiteSaleHour: newStages[i].whiteSaleHour,
                    publicSaleHour: newStages[i].publicSaleHour,
                    startTimeUnixSeconds: newStages[i].startTimeUnixSeconds,
                    endWhiteTimeUnixSeconds: newStages[i].startTimeUnixSeconds +
                        newStages[i].whiteSaleHour *
                        _One_HOUR,
                    endTimeUnixSeconds: newStages[i].startTimeUnixSeconds +
                        (newStages[i].publicSaleHour +
                            newStages[i].whiteSaleHour) *
                        _One_HOUR
                })
            );
        }
    }

    /**
     * @dev Updates info for one stage specified by index (starting from 0).
     */
    function updateStage(
        uint256 index,
        uint80 whiteSalePrice,
        uint80 publicSalePrice,
        uint24 maxStageSupply,
        uint64 startTimeUnixSeconds,
        uint24 whiteSaleHour,
        uint24 publicSaleHour
    ) external onlyOwner {
        if (index >= mintStages.length) revert InvalidStage();
        if (index >= 1) {
            _assertValidStartAndEndTimestamp(
                startTimeUnixSeconds,
                mintStages[index - 1].endTimeUnixSeconds
            );
        }
        mintStages[index].whiteSalePrice = whiteSalePrice;
        mintStages[index].publicSalePrice = publicSalePrice;
        mintStages[index].maxStageSupply = maxStageSupply;
        mintStages[index].startTimeUnixSeconds = startTimeUnixSeconds;
        mintStages[index].whiteSaleHour = whiteSaleHour;
        mintStages[index].publicSaleHour = publicSaleHour;
        mintStages[index].endWhiteTimeUnixSeconds =
            startTimeUnixSeconds +
            whiteSaleHour *
            _One_HOUR;
        mintStages[index].endTimeUnixSeconds =
            startTimeUnixSeconds +
            (publicSaleHour + whiteSaleHour) *
            _One_HOUR;
    }

    function decode(bytes memory data)
        public
        pure
        returns (
            uint32 qty,
            string memory requestId,
            uint64 timestamp,
            bytes memory sig
        )
    {
        (, , , qty, , requestId, timestamp, sig) = abi.decode(
            data,
            (address, address, address, uint32, uint32, string, uint64, bytes)
        );
    }

    function assertValidCosign(bytes memory data)
        internal
        returns (uint32, uint64)
    {
        (
            uint32 qty,
            string memory requestId,
            uint64 timestamp,
            bytes memory sig
        ) = decode(data);
        //   require((expireTime + timestamp >= block.timestamp), "Expired");
        require((!ridvalue[requestId]), "Used");
        ridvalue[requestId] = true;
        if (
            !SignatureChecker.isValidSignatureNow(
                cosigner,
                getCosignDigest(
                    msg.sender,
                    qty,
                    _chainID(),
                    requestId,
                    timestamp
                ),
                sig
            )
        ) {
            revert notSatifiedSig();
        }
        return (qty, timestamp);
    }

    function mint(bytes calldata data) external payable virtual nonReentrant {
        (uint32 qty, uint64 timestamp) = assertValidCosign(data);
        _mintInternal(qty, msg.sender, timestamp);
    }

    function mint_to(address to, bytes calldata data)
        external
        payable
        virtual
        nonReentrant
    {
        (uint32 qty, uint64 timestamp) = assertValidCosign(data);
        _mintInternal(qty, to, timestamp);
    }

    function ownermint(
        address to,
        uint32 qty,
        uint64 timestamp
    ) external payable virtual onlyOwner nonReentrant {
        _mintInternal(qty, to, timestamp);
    }

    function totalMinted() public view virtual returns (uint256) {
        // Counter underflow is impossible as _burnCounter cannot be incremented
        // more than `_currentIndex - _startTokenId()` times.
        return _totalMinted();
    }

    /**
     * @dev Implementation of minting.
     */
    function _mintInternal(
        uint32 qty,
        address to,
        uint64 stageTimestamp
    ) internal {
        require((totalMinted() + qty <= maxSupply), "Over_Max");
        if (!mintable) revert NotMintable();
        uint256 activeStage = getActiveStageFromTimestamp(stageTimestamp);
        if (mintStages[activeStage].endTimeUnixSeconds < block.timestamp)
            revert HasStopped();
        if (
            stageMintedCounts[activeStage] + qty >
            mintStages[activeStage].maxStageSupply
        ) revert NoStageSupplyLeft();

        uint256 price = mintStages[activeStage].publicSalePrice;
        if (stageTimestamp <= mintStages[activeStage].endWhiteTimeUnixSeconds) {
            if (
                mintStages[activeStage].endWhiteTimeUnixSeconds <
                block.timestamp
            ) {
                revert WMStopped();
            }
            price = mintStages[activeStage].whiteSalePrice;
        }
        if (msg.sender != owner()) {
            if (msg.value < price * qty) revert NotEnoughValue();
        }

        stageMintedCounts[activeStage] += qty;
        _safeMint(to, qty);
    }

    function burn(uint256 tokenId) external virtual {
        require((checkStakeEnd(tokenId)), "IN_STAKE");
        _burn(tokenId, true);
    }

    function stake(uint256 tokenId, uint24 _days) external virtual {
        require((ownerOf(tokenId) == msg.sender), "NOT_OWNER");
        require((tokenIdStakeDays[tokenId] == 0), "IN_STAKE");
        tokenIdStakeDays[tokenId] = block.timestamp + _days * _One_DAY;
    }

    function transferFrom(
        address from,
        address to,
        uint256 _tokenId
    ) public payable virtual override {
        require((checkStakeEnd(_tokenId)), "IN_STAKE");
        super.transferFrom(from, to, _tokenId);
    }

    function checkStakeEnd(uint256 tokenId) internal view returns (bool) {
        uint256 endTime = tokenIdStakeDays[tokenId];
        return block.timestamp >= endTime;
    }

    function withdraw() external {
        require(msg.sender == beneficiary);
        uint256 value = address(this).balance;
        (bool success, ) = msg.sender.call{value: value}("");
        if (!success) revert WithdrawFailed();
        emit Withdraw(value);
    }

    /**
     * @dev Sets token base URI.
     */
    function setBaseURI(string calldata baseURI) external onlyOwner {
        currentBaseURI = baseURI;
    }

    /**
     * @dev Sets token URI suffix. e.g. ".json".
     */
    function setTokenURISuffix(string calldata suffix) external onlyOwner {
        tokenURISuffix = suffix;
    }

    /**
     * @dev Returns token URI for a given token id.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721A)
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = currentBaseURI;
        return
            bytes(baseURI).length != 0
                ? string(
                    abi.encodePacked(
                        baseURI,
                        _toString(tokenId),
                        tokenURISuffix
                    )
                )
                : "";
    }

    /**
     * @dev Returns data hash for the given minter, qty and timestamp.
     */
    function getCosignDigest(
        address sender,
        uint32 qty,
        uint32 chainId,
        string memory requestId,
        uint64 timestamp
    ) internal view returns (bytes32) {
        bytes32 _msgHash = keccak256(
            abi.encodePacked(
                address(this),
                sender,
                cosigner,
                qty,
                chainId,
                requestId,
                timestamp
            )
        );
        return toEthSignedMessageHash(_msgHash);
    }

    function toEthSignedMessageHash(bytes32 hash)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    /**
     * @dev Returns the current active stage based on timestamp.
     */
    function getActiveStageFromTimestamp(uint64 timestamp)
        public
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < mintStages.length; i++) {
            if (
                timestamp >= mintStages[i].startTimeUnixSeconds &&
                timestamp < mintStages[i].endTimeUnixSeconds
            ) {
                return i;
            }
        }
        revert InvalidStage();
    }

    /**
     * @dev Validates the start timestamp is before end timestamp. Used when updating stages.
     */
    function _assertValidStartAndEndTimestamp(uint256 start, uint256 end)
        internal
        pure
    {
        if (start < end) revert InvalidStartAndEndTimestamp();
    }

    /**
     * @dev Returns chain id.
     */
    function _chainID() public view returns (uint32) {
        uint32 chainID;
        assembly {
            chainID := chainid()
        }
        return chainID;
    }

    /**
     * @dev Returns number of stages.
     */
    function getNumberStages() external view virtual returns (uint256) {
        return mintStages.length;
    }

    function gettimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ONFT721Core, ERC721A)
        returns (bool)
    {
        return
            interfaceId == type(IONFT721Core).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _debitFrom(
        address _from,
        uint16,
        bytes memory,
        uint256 _tokenId
    ) internal virtual override(ONFT721Core) {
        require((checkStakeEnd(_tokenId)), "IN_STAKE");
        safeTransferFrom(_from, address(this), _tokenId);
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _tokenId
    ) internal virtual override(ONFT721Core) {
        require(
            !_exists(_tokenId) ||
                (_exists(_tokenId) && ownerOf(_tokenId) == address(this))
        );
        if (!_exists(_tokenId)) {
            _safeMint(_toAddress, _tokenId);
        } else {
            safeTransferFrom(address(this), _toAddress, _tokenId);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external virtual override returns (bytes4) {
        return ERC721A__IERC721Receiver.onERC721Received.selector;
    }
}
