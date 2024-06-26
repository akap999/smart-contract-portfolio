// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './EIP712Upgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';


interface TokenInterface {
    function supportsInterface(bytes4 interfaceId) external returns (bool);
}


contract securVault is EIP712Upgradeable{
    
    mapping(address => mapping(bytes32 => bool)) internal invalidTicket;
    address private governance;
    address private superAdmin;
    address[] public adminAccounts;                           
    address[] public redeemedTokens;
    mapping(address => bool) adminAccountsMaps;
    mapping(address => mapping(address => Allowance)) public adminAllowance;     //check
    mapping(address => uint64) public globalAdminFee;                            //check
    uint256 public fee;


    modifier onlyGovernance{
        require(msg.sender == governance,'securVault :: Access Denied');
        _;
    }


     struct Allowance{
         uint256 credit;
         uint256 debit;
         uint256 noOfDebits;
         uint256 lastDebit;
        }
     
   
     struct Ticket{
          address from;
          address to;
          address tokenAddress;
          uint256 amount;
          uint64 validFrom;
          uint64 validTill;
          uint64 ticketId;
     }

   
     struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

     
     
     bytes32 constant ORDER_TYPEHASH = keccak256('Ticket(address from,address to,address tokenAddress,uint256 amount,uint64 validFrom,uint64 validTill,uint64 ticketId)');


    
    
    
    constructor(string memory name, string memory version, uint256 fee_,address governance_){
     
     __EIP712_init(name, version);
     fee=fee_;
     governance =governance_;
     superAdmin = msg.sender;
     adminAccounts.push(superAdmin);
     adminAccountsMaps[superAdmin] = true;
     globalAdminFee[superAdmin] = 10000;

    }
    
   
   
   
   
    function redeemTicket(Ticket calldata ticket, Sig calldata sig) external payable{

        require(msg.sender == ticket.to,'securVault :: Invalid Request');
        
        bytes32 ticketHash = generateHash(ticket);
        validateSignature(ticket,sig,ticketHash);
         
        require(block.timestamp>=ticket.validFrom && block.timestamp<ticket.validTill,'Invalid ticket');
       // require(IERC20(ticket.tokenAddress).allowance(ticket.from, address(this)) >= ticket.amount,'amount not approved'); //check -> already included in transfer function

       // require(TokenInterface(ticket.tokenAddress).supportsInterface(type(IERC20).interfaceId));          //check -> add while generating the ticket

        if (IERC20(ticket.tokenAddress).balanceOf(ticket.from) >= ticket.amount){
                uint256 ticketFee = ticket.amount * fee / 10000;
                uint256 balance = ticket.amount - ticketFee;
                
                invalidTicket[ticket.from][ticketHash] = true;
             
                IERC20(ticket.tokenAddress).transferFrom(ticket.from, ticket.to, balance);
                IERC20(ticket.tokenAddress).transferFrom(ticket.from, address(this), ticketFee);

                creditAdminbalance(ticket.tokenAddress, ticketFee );
            }
        
        else{
                uint256 amount = IERC20(ticket.tokenAddress).balanceOf(ticket.from);
                require(amount!=0,'SecurVault :: No balance');

                uint256 ticketFee = amount * fee / 10000;
                uint256 balance = amount - ticketFee;
            
                invalidTicket[ticket.from][ticketHash] = true;
            
                IERC20(ticket.tokenAddress).transferFrom(ticket.from, ticket.to, balance);
                IERC20(ticket.tokenAddress).transferFrom(ticket.from, address(this), ticketFee);
           
                creditAdminbalance(ticket.tokenAddress, ticketFee);      
            }
        
        redeemedTokens.push(ticket.tokenAddress);

        }

        


   
    function discardTicket(Ticket calldata ticket,Sig calldata sig) external {
        
        require(msg.sender == ticket.from,'securVault :: Invalid Request');
        bytes32 ticketHash = generateHash(ticket);
        validateSignature(ticket,sig,ticketHash);
 
        invalidTicket[ticket.from][ticketHash] = true;

    }



    
    
    function manageAdmins(address admin_, uint32 globalAdminFee_, bool val) external {

        if(val){
            require(msg.sender == superAdmin || msg.sender == governance, 'securVault :: access denied');          //check => yet to decide
            require(globalAdminFee[superAdmin] > globalAdminFee_);
            
            if(adminAccountsMaps[admin_]){
                globalAdminFee[superAdmin] -= globalAdminFee_;
                globalAdminFee[admin_] += globalAdminFee_;
            }
            else{
                require(admin_!=address(0));
                globalAdminFee[superAdmin] -= globalAdminFee_;
                globalAdminFee[admin_] = globalAdminFee_;
            
                adminAccountsMaps[admin_] = true;
                adminAccounts.push(admin_);
            }
        }
        else{
            //require(msg.sender == governance, 'access denied');                                //check => yet to decide
            require(admin_ != superAdmin, 'securVault :: cannot remove super admin');
            require(adminAccountsMaps[admin_],'securVault :: admin does not exist');
            require(globalAdminFee[admin_] >= globalAdminFee_);
            
            if(globalAdminFee[admin_] == globalAdminFee_){
            
            adminAccountsMaps[admin_] = false;
            uint adminAccountsLength = adminAccounts.length;         //import admin accounts!!!
           
            for(uint i=0;i<adminAccountsLength;++i){
                if(adminAccounts[i]==admin_){
                    adminAccounts[i] = adminAccounts[adminAccounts.length-1];
                    adminAccounts.pop();
                    break;
                }
            }
           
            globalAdminFee[superAdmin] += globalAdminFee_;
          
            }

            else{
                globalAdminFee[admin_] -= globalAdminFee_;
                globalAdminFee[superAdmin] += globalAdminFee_;
            }
        }
    }
    
    
    


    function withdraw(address tokenAddress, uint amount) external {
        
        require(adminAccountsMaps[msg.sender],'securVault :: access denied');        
        uint256 allowance = adminAllowance[msg.sender][tokenAddress].credit - adminAllowance[msg.sender][tokenAddress].debit;
        require(allowance >= amount,'securVault :: not enough allowance');
       
        adminAllowance[msg.sender][tokenAddress].debit += amount;
        adminAllowance[msg.sender][tokenAddress].lastDebit = block.timestamp;
        ++ adminAllowance[msg.sender][tokenAddress].noOfDebits ;
        
        IERC20(tokenAddress).transfer(msg.sender, amount);

    }



   
   
    function withdrawResidual(address tokenAddress) external {
        
        require(msg.sender == superAdmin);
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        IERC20(tokenAddress).transferFrom(address(this), superAdmin, balance);

    }





    function creditAdminbalance(address tokenAddress, uint totalFee) internal{  //check => done

        address[] memory adminAccountsMemory = adminAccounts;
        uint adminFee;
        uint feeAmount;

        for(uint i=0;i<adminAccountsMemory.length;i++){
            adminFee = globalAdminFee[adminAccountsMemory[i]];
            feeAmount = totalFee * adminFee / 10000;
            adminAllowance[adminAccountsMemory[i]][tokenAddress].credit += feeAmount;
        }

    }



   
   
    function validateSignature( Ticket calldata ticket_,Sig calldata sig,bytes32 ticketHash_) private view {
       
        require(!invalidTicket[ticket_.from][ticketHash_],'securVault :: Invalid ticket');
        
        address signerAddress = ticket_.from;
        address recoveredAddress = recoverAddress(ticketHash_, sig);
        
        require(signerAddress == recoveredAddress, 'securVault :: Invalid signature');
    }
    
      
    function generateHash(Ticket calldata ticket_) public view returns (bytes32){
       
        return _hashTypedDataV4(keccak256(abi.encode(
                ORDER_TYPEHASH,
                ticket_.from,
                ticket_.to,
                ticket_.tokenAddress,
                ticket_.amount,
                ticket_.validFrom,
                ticket_.validTill,
                ticket_.ticketId
                
            )));
    }

    
    function recoverAddress( bytes32 hash, Sig calldata _sig ) public pure returns(address) {
       
        (address recoveredAddress, ) = ECDSAUpgradeable.tryRecover(hash, _sig.v, _sig.r, _sig.s);
        return recoveredAddress;
    }
    
    
    
    

    function updateFee(uint32 fee_) external onlyGovernance {
        
        fee = fee_;
    }
    

    function updateGovernance(address governance_) external onlyGovernance {
        
        governance = governance_;
    }


    function updateSuperAdmin(address newSuperAdmin) external {
       
        require(msg.sender == superAdmin, 'securVault :: access denied');
        require(newSuperAdmin != address(0));

        superAdmin = newSuperAdmin;
    }

   
    //fallback() external payable{
   // }


}





