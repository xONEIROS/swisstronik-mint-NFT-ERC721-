#!/bin/bash

print_blue() {
    echo -e "\033[34m$1\033[0m"
}

print_red() {
    echo -e "\033[31m$1\033[0m"
}

print_green() {
    echo -e "\033[32m$1\033[0m"
}

print_pink() {
    echo -e "\033[95m$1\033[0m"
}

prompt_for_input() {
    read -p "$1" input
    echo $input
}

menu() {
    clear
    echo "_._._ ONEIROS is Here ! _._._"
    echo "Please select a script to run:"
    echo "1) Deploy and mint NFT (ERC721)"
    echo "2) Deploy and mint ERC20 Token"
    echo "3) Deploy and interact with Proxy Contract"
    echo "4) Exit"
    echo
    read -p "Enter your choice [1-4]: " choice
    case $choice in
        1)
            run_erc721
            ;;
        2)
            run_erc20
            ;;
        3)
            run_proxy
            ;;
        4)
            exit 0
            ;;
        *)
            echo "Invalid choice!"
            menu
            ;;
    esac
}

run_erc721() {
    echo "Running ERC721 script..."
    print_blue "Installing dependencies..."
    npm install --save-dev hardhat
    npm install dotenv
    npm install @swisstronik/utils
    npm install @openzeppelin/contracts
    echo "Installation completed."

    print_blue "Installing Hardhat and necessary dependencies..."
    npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox

    print_blue "Removing default package.json file..."
    rm package.json

    print_blue "Creating package.json file again..."
    cat <<EOL > package.json
{
  "name": "hardhat-project",
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^3.0.0",
    "hardhat": "^2.17.1"
  },
  "dependencies": {
    "@openzeppelin/contracts": "^5.0.0",
    "@swisstronik/utils": "^1.2.1"
  }
}
EOL

    print_blue "Initializing Hardhat project..."
    npx hardhat

    print_blue "Removing the default Hardhat configuration file..."
    rm hardhat.config.js
    read -p "Enter your wallet private key: " PRIVATE_KEY

    if [[ $PRIVATE_KEY != 0x* ]]; then
      PRIVATE_KEY="0x$PRIVATE_KEY"
    fi

    cat <<EOL > hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.20",
  networks: {
    swisstronik: {
      url: "https://json-rpc.testnet.swisstronik.com/",
      accounts: ["$PRIVATE_KEY"],
    },
  },
};
EOL

    print_blue "Hardhat configuration file has been updated."
    rm -f contracts/Lock.sol
    sleep 2

    print_pink "Enter NFT NAME:"
    read -p "" NFT_NAME
    print_pink "Enter NFT SYMBOL:"
    read -p "" NFT_SYMBOL
    cat <<EOL > contracts/NFT.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PrivateNFT is ERC721, ERC721Burnable, Ownable {
    constructor(address initialOwner)
        ERC721("$NFT_NAME","$NFT_SYMBOL")
        Ownable(initialOwner)
    {}

    function safeMint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }

    function balanceOf(address owner) public view override returns (uint256) {
        require(msg.sender == owner, "PrivateNFT: msg.sender != owner");
        return super.balanceOf(owner);
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = super.ownerOf(tokenId);
        require(msg.sender == owner, "PrivateNFT: msg.sender != owner");
        return owner;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address owner = super.ownerOf(tokenId);
        require(msg.sender == owner, "PrivateNFT: msg.sender != owner");
        return super.tokenURI(tokenId);
    }
}
EOL
    echo "PrivateNFT.sol contract created."

    echo "Compiling the contract..."
    npx hardhat compile
    echo "Contract compiled."

    echo "Creating deploy.js script..."
    mkdir -p scripts
    cat <<EOL > scripts/deploy.js
const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const contractFactory = await hre.ethers.getContractFactory("PrivateNFT");
  const contract = await contractFactory.deploy(deployer.address);
  await contract.waitForDeployment();
  const deployedContract = await contract.getAddress();
  fs.writeFileSync("contract.txt", deployedContract);
  console.log(\`Contract deployed to \${deployedContract}\`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL
    echo "deploy.js script created."

    echo "Deploying the contract..."
    npx hardhat run scripts/deploy.js --network swisstronik
    echo "Contract deployed."

    echo "Creating mint.js script..."
    cat <<EOL > scripts/mint.js
const hre = require("hardhat");
const fs = require("fs");
const { encryptDataField, decryptNodeResponse } = require("@swisstronik/utils");

const sendShieldedTransaction = async (signer, destination, data, value) => {
  const rpcLink = hre.network.config.url;
  const [encryptedData] = await encryptDataField(rpcLink, data);
  return await signer.sendTransaction({
    from: signer.address,
    to: destination,
    data: encryptedData,
    value,
  });
};

async function main() {
  const contractAddress = fs.readFileSync("contract.txt", "utf8").trim();
  const [signer] = await hre.ethers.getSigners();
  const contractFactory = await hre.ethers.getContractFactory("PrivateNFT");
  const contract = contractFactory.attach(contractAddress);
  const functionName = "safeMint";
  const safeMintTx = await sendShieldedTransaction(
    signer,
    contractAddress,
    contract.interface.encodeFunctionData(functionName, [signer.address, 1]),
    0
  );
  await safeMintTx.wait();
  console.log("Transaction Receipt: ", \`Minting NFT has been success! Transaction hash: https://explorer-evm.testnet.swisstronik.com/tx/\${safeMintTx.hash}\`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL
    echo "mint.js script created."

    echo "Minting NFT..."
    npx hardhat run scripts/mint.js --network swisstronik
    echo "NFT minted."

    print_green "Copy the above Tx URL and save it somewhere, you need to submit it on Testnet page"
    sed -i 's/0x[0-9a-fA-F]*,\?\s*//g' hardhat.config.js
    print_blue "PRIVATE_KEY has been removed from hardhat.config.js."
    print_blue "Pushing these files to your github Repo link"
    git add . && git commit -m "Initial commit" && git push origin main
}

run_erc20() {
    echo "Running ERC20 script..."
    print_blue "Installing Hardhat and necessary dependencies..."
    npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox

    print_blue "Removing default package.json file..."
    rm package.json

    print_blue "Creating package.json file again..."
    cat <<EOL > package.json
{
  "name": "hardhat-project",
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^3.0.0",
    "hardhat": "^2.17.1"
  },
  "dependencies": {
    "@openzeppelin/contracts": "^4.9.3",
    "@swisstronik/utils": "^1.2.1"
  }
}
EOL

    print_blue "Initializing Hardhat project..."
    npx hardhat

    print_blue "Removing the default Hardhat configuration file..."
    rm hardhat.config.js
    read -p "Enter your wallet private key: " PRIVATE_KEY

    if [[ $PRIVATE_KEY != 0x* ]]; then
      PRIVATE_KEY="0x$PRIVATE_KEY"
    fi

    cat <<EOL > hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.19",
  networks: {
    swisstronik: {
      url: "https://json-rpc.testnet.swisstronik.com/",
      accounts: ["$PRIVATE_KEY"],
    },
  },
};
EOL

    print_blue "Hardhat configuration file has been updated."
    rm -f contracts/Lock.sol
    sleep 2

    print_pink "Enter TOKEN NAME:"
    read -p "" TOKEN_NAME
    print_pink "Enter TOKEN SYMBOL:"
    read -p "" TOKEN_SYMBOL
    cat <<EOL > contracts/Token.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor()ERC20("$TOKEN_NAME","$TOKEN_SYMBOL"){} 

    function mint100tokens() public {
        _mint(msg.sender,100*10**18);
    }

    function burn100tokens() public{
        _burn(msg.sender,100*10**18);
    }
    
}
EOL

    npm install
    print_blue "Compiling the contract..."
    npx hardhat compile

    print_blue "Creating scripts directory and the deployment script..."
    mkdir -p scripts

    cat <<EOL > scripts/deploy.js
const hre = require("hardhat");

async function main() {
  const contract = await hre.ethers.deployContract("TestToken");

  await contract.waitForDeployment();

  console.log(\`Contract address : \${contract.target}\`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL

    npx hardhat run scripts/deploy.js --network swisstronik

    print_green "Contract deployment successful, Copy the above contract address and save it somewhere, you need to submit it in Testnet website"
    print_blue "Creating mint.js file..."
    read -p "Enter yours Token Contract Address: " CONTRACT_ADDRESS

    cat <<EOL > scripts/mint.js
const hre = require("hardhat");
const { encryptDataField, decryptNodeResponse } = require("@swisstronik/utils");
const sendShieldedTransaction = async (signer, destination, data, value) => {
  const rpcLink = hre.network.config.url;
  const [encryptedData] = await encryptDataField(rpcLink, data);
  return await signer.sendTransaction({
    from: signer.address,
    to: destination,
    data: encryptedData,
    value,
  });
};

async function main() {
  const contractAddress = "$CONTRACT_ADDRESS";
  const [signer] = await hre.ethers.getSigners();

  const contractFactory = await hre.ethers.getContractFactory("TestToken");
  const contract = contractFactory.attach(contractAddress);

  const functionName = "mint100tokens";
  const mint100TokensTx = await sendShieldedTransaction(
    signer,
    contractAddress,
    contract.interface.encodeFunctionData(functionName),
    0
  );

  await mint100TokensTx.wait();

  console.log("Transaction Receipt: ", mint100TokensTx.hash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL

    cat <<EOL > scripts/transfer.js
const hre = require("hardhat");
const { encryptDataField, decryptNodeResponse } = require("@swisstronik/utils");
const sendShieldedTransaction = async (signer, destination, data, value) => {
  const rpcLink = hre.network.config.url;
  const [encryptedData] = await encryptDataField(rpcLink, data);
  return await signer.sendTransaction({
    from: signer.address,
    to: destination,
    data: encryptedData,
    value,
  });
};

async function main() {
  const replace_contractAddress = "$CONTRACT_ADDRESS";
  const [signer] = await hre.ethers.getSigners();

  const replace_contractFactory = await hre.ethers.getContractFactory("TestToken");
  const contract = replace_contractFactory.attach(replace_contractAddress);

  const replace_functionName = "transfer";
  const replace_functionArgs = ["0x16af037878a6cAce2Ea29d39A3757aC2F6F7aac1", "1"];
  const transaction = await sendShieldedTransaction(signer, replace_contractAddress, contract.interface.encodeFunctionData(replace_functionName, replace_functionArgs), 0);

  await transaction.wait();
  console.log("Transfer Transaction Hash:", \`https://explorer-evm.testnet.swisstronik.com/tx/\${transaction.hash}\`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL

    print_blue "Minting $TOKEN_SYMBOL..."
    npx hardhat run scripts/mint.js --network swisstronik
    print_blue "Transferring $TOKEN_SYMBOL..."
    npx hardhat run scripts/transfer.js --network swisstronik
    print_green "Copy the above Tx URL and save it somewhere, you need to submit it on Testnet page"
    sed -i 's/0x[0-9a-fA-F]*,\?\s*//g' hardhat.config.js
    print_blue "PRIVATE_KEY has been removed from hardhat.config.js."
    print_blue "Pushing these files to your github Repo link"
    git add . && git commit -m "Initial commit" && git push origin main
}

run_proxy() {
    echo "Running Proxy script..."
    print_blue "Installing dependencies..."
    npm install --save-dev hardhat
    npm install dotenv
    npm install @swisstronik/utils
    npm install @openzeppelin/hardhat-upgrades
    npm install @openzeppelin/contracts
    npm install @nomicfoundation/hardhat-toolbox
    echo "Installation completed."

    echo "Creating a Hardhat project..."
    npx hardhat

    rm -f contracts/Lock.sol
    echo "Lock.sol removed."

    echo "Hardhat project created."

    echo "Installing Hardhat toolbox..."
    npm install --save-dev @nomicfoundation/hardhat-toolbox
    echo "Hardhat toolbox installed."

    echo "Creating .env file..."
    read -p "Enter your private key: " PRIVATE_KEY
    echo "PRIVATE_KEY=$PRIVATE_KEY" > .env
    echo ".env file created."

    echo "Configuring Hardhat..."
    cat <<EOL > hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    swisstronik: {
      url: "https://json-rpc.testnet.swisstronik.com/",
      accounts: [\`0x\${process.env.PRIVATE_KEY}\`],
    },
  },
};
EOL
    echo "Hardhat configuration completed."

    echo "Creating Hello_swtr.sol contract..."
    mkdir -p contracts
    cat <<EOL > contracts/Hello_swtr.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract Swisstronik {
    string private message;

    function initialize(string memory _message) public {
        message = _message;
    }

    function setMessage(string memory _message) public {
        message = _message;
    }

    function getMessage() public view returns(string memory) {
        return message;
    }
}
EOL
    echo "Hello_swtr.sol contract created."

    echo "Compiling the contract..."
    npx hardhat compile
    echo "Contract compiled."

    echo "Creating deploy.js script..."
    mkdir -p scripts
    cat <<EOL > scripts/deploy.js
const fs = require("fs");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const Swisstronik = await ethers.getContractFactory('Swisstronik');
  const swisstronik = await Swisstronik.deploy();
  await swisstronik.waitForDeployment(); 
  console.log('Non-proxy Swisstronik deployed to:', swisstronik.target);
  fs.writeFileSync("contract.txt", swisstronik.target);

  console.log(\`Deployment transaction hash: https://explorer-evm.testnet.swisstronik.com/address/\${swisstronik.target}\`);

  console.log('');
  
  const upgradedSwisstronik = await upgrades.deployProxy(Swisstronik, ['Hello Swisstronik from Happy Cuan Airdrop!!'], { kind: 'transparent' });
  await upgradedSwisstronik.waitForDeployment(); 
  console.log('Proxy Swisstronik deployed to:', upgradedSwisstronik.target);
  fs.writeFileSync("proxiedContract.txt", upgradedSwisstronik.target);

  console.log(\`Deployment transaction hash: https://explorer-evm.testnet.swisstronik.com/address/\${upgradedSwisstronik.target}\`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
EOL
    echo "deploy.js script created."

    echo "Deploying the contract..."
    npx hardhat run scripts/deploy.js --network swisstronik
    echo "Contract deployed."

    echo "Creating setMessage.js script..."
    cat <<EOL > scripts/setMessage.js
const hre = require("hardhat");
const { encryptDataField, decryptNodeResponse } = require("@swisstronik/utils");
const fs = require("fs");

const sendShieldedTransaction = async (signer, destination, data, value) => {
  const rpclink = hre.network.config.url;
  const [encryptedData] = await encryptDataField(rpclink, data);
  return await signer.sendTransaction({
    from: signer.address,
    to: destination,
    data: encryptedData,
    value,
  });
};

async function main() {
  const contractAddress = fs.readFileSync("proxiedContract.txt", "utf8").trim();
  const [signer] = await hre.ethers.getSigners();
  const contractFactory = await hre.ethers.getContractFactory("Swisstronik");
  const contract = contractFactory.attach(contractAddress);
  const functionName = "setMessage";
  const messageToSet = "Hello Swisstronik from Happy Cuan Airdrop!!";
  const setMessageTx = await sendShieldedTransaction(signer, contractAddress, contract.interface.encodeFunctionData(functionName, [messageToSet]), 0);
  await setMessageTx.wait();
  console.log("Transaction Receipt: ", setMessageTx);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL
    echo "setMessage.js script created."

    echo "Running setMessage.js..."
    npx hardhat run scripts/setMessage.js --network swisstronik
    echo "Message set."

    echo "Creating getMessage.js script..."
    cat <<EOL > scripts/getMessage.js
const hre = require("hardhat");
const { encryptDataField, decryptNodeResponse } = require("@swisstronik/utils");
const fs = require("fs");

const sendShieldedQuery = async (provider, destination, data) => {
  const rpclink = hre.network.config.url;
  const [encryptedData, usedEncryptedKey] = await encryptDataField(rpclink, data);
  const response = await provider.call({
    to: destination,
    data: encryptedData,
  });
  return await decryptNodeResponse(rpclink, response, usedEncryptedKey);
};

async function main() {
  const contractAddress = fs.readFileSync("proxiedContract.txt", "utf8").trim();
  const [signer] = await hre.ethers.getSigners();
  const contractFactory = await hre.ethers.getContractFactory("Swisstronik");
  const contract = contractFactory.attach(contractAddress);
  const functionName = "getMessage";
  const responseMessage = await sendShieldedQuery(signer.provider, contractAddress, contract.interface.encodeFunctionData(functionName));
  console.log("Decoded response:", contract.interface.decodeFunctionResult(functionName, responseMessage)[0]);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL
    echo "getMessage.js script created."

    echo "Running getMessage.js..."
    npx hardhat run scripts/getMessage.js --network swisstronik
    echo "Message retrieved."

    print_green "Copy the above Tx URL and save it somewhere, you need to submit it on Testnet page"
    sed -i 's/0x[0-9a-fA-F]*,\?\s*//g' .env
    print_blue "PRIVATE_KEY has been removed from .env."

    print_blue "Pushing these files to your github Repo link"
    git add . && git commit -m "Initial commit" && git push origin main
}

menu
