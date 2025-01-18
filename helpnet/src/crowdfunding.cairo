use starknet::{ContractAddress, get_caller_address, get_block_timestamp, contract_address_const, get_contract_address};

#[starknet::interface]
pub trait IHelpnet<TContractState> {
    // create campaign
    fn create_campaign(ref self: TContractState, start_balance: u128, name: felt252, target: u128, deadline: u64, description: felt252);

    /// Retrieve contract balance.
    fn pledge(ref self: TContractState, name: felt252, amount: u128);

    // A pledger changes his mind
    fn unpledge(ref self: TContractState, name: felt252, amount: u128);

    //Refund contributors if the target is not met
    fn refund(ref self: TContractState, name: felt252);


    // withdraw contribution after target are met
    fn withdraw(ref self: TContractState, name: felt252, amount: u128, recipient: ContractAddress);

    //view campaign progress
    fn viewProgress(self: @TContractState, name: felt252) -> campaign ;

}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct campaign {
     creator: ContractAddress,
     id: u128,
     target: u128,
     start_balance: u128,
     start_at: u64,
     deadline: u64,
     description: felt252,
    }


#[starknet::contract]
mod Helpnet {
    use starknet::storage::{Map};
    use starknet::ContractAddress;
    use super::{get_caller_address, get_block_timestamp, contract_address_const, get_contract_address};
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry};
    use super::campaign;
     use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};


 
   #[storage]
   struct Storage {
     id: u128,
     Current_balance: u128,
     name_id: Map<felt252, u128>,   
     campaigns: Map<u128, campaign>,
     campaign_by_name: Map<felt252, campaign>,
     balances: Map<ContractAddress, u128>,
     num_campaigns: u128,
    
     
   }


   #[event]
   #[derive(Drop, starknet::Event)]
   pub enum Event {
    createCampaign: createCampaign,
    place_pledge: place_pledge,
    un_pledge: un_pledge,
    re_fund: re_fund,
    fund_withdraw: fund_withdraw,
   }
 
   #[derive(Drop, starknet::Event)]
   pub struct createCampaign{
        creator: ContractAddress,
        target: u128,
        start_balance: u128,
        start_at: u64,
        deadline: u64,
        id: u128,
        description: felt252,
   }

   #[derive(Drop, starknet::Event)]
   pub struct place_pledge {
     name: felt252,
     pledger: ContractAddress,
     amount: u128,
     balance: u128,
   }

#[derive(Drop, starknet::Event)]
pub struct un_pledge {
     name: felt252,
     pledger: ContractAddress,
     amount: u128,
     balance: u128,
}

#[derive(Drop, starknet::Event)]
pub struct re_fund {
     name: felt252,
     amount: u128,
     to: ContractAddress,
     balance: u128,
}

#[derive(Drop, starknet::Event)]
pub struct fund_withdraw{
     name: felt252,
     amount: u128,
     from: ContractAddress,
     to: ContractAddress,
}



   #[abi(embed_v0)]
   impl HelpnetImpl of super::IHelpnet<ContractState> {

    fn create_campaign(ref self: ContractState, start_balance: u128, name: felt252, target: u128, deadline: u64, description: felt252) {

     let start_at = get_block_timestamp();
     let _deadline = start_at + deadline;
     let creator = get_caller_address();
     let campaign_contract_address = get_contract_address();
     let campaign_balance = self.Current_balance.read();

     let current_id = self.id.read();
     let updated_id = current_id + 1;

     assert(deadline > 0, 'invalid duration');

    // self.name_id.write(name, updated_id);
     self.name_id.entry(name).write(updated_id);
   
     self.Current_balance.write(self.Current_balance.read() + start_balance);

          
          let _new_campaign = campaign {
               creator: creator,
               target: target,
               start_balance: start_balance,
               start_at: start_at,
               deadline: _deadline,
               id: updated_id,
               description: description,
          };

          self.campaigns.entry(updated_id).write(_new_campaign);

          self.campaign_by_name.entry(name).write(_new_campaign);

         self.num_campaigns.write(self.num_campaigns.read() + 1);

         self.balances.entry(creator).write(start_balance);
         self.balances.entry(campaign_contract_address).write(campaign_balance);

         self.Current_balance.write(self.Current_balance.read() + start_balance);
         //transfer from start balance to creator
         self._transfer(creator, start_balance);

         self.emit(createCampaign { creator: creator,
          target: target,
          start_balance: start_balance,
          start_at: start_at,
          deadline: deadline,
          id: updated_id,
          description: description, });

    }

    /// Retrieve contract balance.
   fn pledge(ref self: ContractState, name: felt252, amount: u128) {


      let _campaign: campaign = self.campaign_by_name.entry(name).read();
      let campaign_contract_address = get_contract_address();
     // let campaign_balance = self.Current_balance.read();
 
      let current_time = get_block_timestamp();
      let _pledger = get_caller_address();
      

          assert(current_time < _campaign.deadline, 'Campaign ended');
          assert(current_time >=  _campaign.start_at, 'Campaign not started');

          // updating the balance
          self.Current_balance.write(self.Current_balance.read() + amount);
          let updated_balance: u128 = self.Current_balance.read();

          //keeping track of users and their pledges
          self.balances.entry(get_caller_address()).write(amount);

          // transfer funds
          self._transfer_from(_pledger,campaign_contract_address, amount);

          self.emit(place_pledge {  name: name,
               amount: amount,
               pledger: _pledger,
               balance: updated_balance,});
    }
   

    // A pledger changes his mind
    fn unpledge(ref self: ContractState, name: felt252, amount: u128) {

     let _campaign: campaign = self.campaign_by_name.entry(name).read();
     let campaign_contract_address = get_contract_address();

     let current_time = get_block_timestamp();

     let _unpledger = get_caller_address();

     let pledger_balance = self.balances.entry(_unpledger).read();   

         
          assert(current_time < _campaign.deadline, 'Campaign ended');
          assert(amount <= pledger_balance, 'Insufficient funds');
        
          self._transfer_from(campaign_contract_address, _unpledger, amount);

      // updating the balance
      self.Current_balance.write(self.Current_balance.read() - amount);
      let updated_balance: u128 = self.Current_balance.read();



      self.emit(un_pledge {  name: name,
          amount: amount,
          pledger: _unpledger,
          balance: updated_balance,});
        
    }

    // withdraw contribution after target are met
    fn withdraw(ref self: ContractState, name: felt252, amount: u128, recipient: ContractAddress ) {
      
     let _campaign: campaign = self.campaign_by_name.entry(name).read();
     let campaign_contract_address = get_contract_address();
    // let campaign_balance = self.Current_balance.read();

     let current_time = get_block_timestamp();
     
     let withdrawer = get_caller_address(); 

     

     assert(campaign_contract_address == withdrawer, 'Not authorized');
     assert(current_time >= _campaign.deadline, 'Campaign is not ended');

     let campaign_balance = self.balances.entry(campaign_contract_address).read();
     let _recipient_amount = self.balances.entry(recipient).read();

     let current_amount = campaign_balance - amount;

     self.Current_balance.write(self.Current_balance.read() - amount);

    // self.balances.entry(recipient).write(self.balances.);
     self.balances.entry(campaign_contract_address).write(current_amount);
     
     self.balances.entry(recipient).write(_recipient_amount + amount);

     self.Current_balance.write(self.Current_balance.read() - amount);

     self._transfer_from(campaign_contract_address, recipient, amount);

     self.emit(fund_withdraw {
          name: name,
          amount: amount,
          from: campaign_contract_address,
          to: recipient,
     });

     
    }


    //Refund contributors if the target is not met
    fn refund(ref self: ContractState, name: felt252) {
          let _campaign: campaign = self.campaign_by_name.entry(name).read();
          let campaign_contract_address = get_contract_address();

          let _caller = get_caller_address();
          let current_time = get_block_timestamp();
          //let creator_address = _campaign.creator;  



          let _pledgeramount = self.balances.entry(_caller).read();

          let _balance = self.Current_balance.read() - _pledgeramount;

          // assert(_caller == _campaign.creator, 'Not the creator');
          assert(current_time >= _campaign.deadline, 'Campaign is still active');

        self._transfer_from(campaign_contract_address, _caller, _pledgeramount);

        self.Current_balance.write(_balance);


          self.emit(re_fund {
            name: name,
            amount: _pledgeramount,
            to: _caller,
            balance: _balance,
       });
     
    }



    fn viewProgress(self: @ContractState, name: felt252) -> campaign {
     let _campaign: campaign = self.campaign_by_name.entry(name).read();
     
     let check = campaign {
          creator: _campaign.creator,
         id: _campaign.id,
        target: _campaign.target,
        start_balance: _campaign.start_balance,
       start_at: _campaign.start_at,
       deadline: _campaign.deadline,
       description: _campaign.description,
     };

     check

    
    }

   }





#[generate_trait]            
impl ERC20Impl of ERC20Trait {
    
    fn _transfer_from(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u128) {
        let eth_dispatcher = IERC20Dispatcher {
            contract_address: contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>() // STRK token Contract Address
        };
        assert(eth_dispatcher.balance_of(sender) >= amount.into(), 'insufficient funds');

        // eth_dispatcher.approve(validator_contract_address, amount.into()); This is wrong as it is the validator contract trying to approve itself
        let success = eth_dispatcher.transfer_from(sender, recipient, amount.into());
        assert(success, 'ERC20 transfer_from fail!');
    }

    fn _transfer(ref self: ContractState, recipient: ContractAddress, amount: u128) {
        let eth_dispatcher = IERC20Dispatcher {
            contract_address: contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>() // STRK token Contract Address
        };
        let success = eth_dispatcher.transfer(recipient, amount.into());
        assert(success, 'ERC20 transfer fail!');
    }
}
}

