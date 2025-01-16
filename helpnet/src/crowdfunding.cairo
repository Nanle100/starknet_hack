use starknet::{ContractAddress, get_caller_address, get_block_timestamp};

#[starknet::interface]
pub trait IHelpnet<TContractState> {
    // create campaign
    fn create_campaign(ref self: TContractState, start_balance: u64, name: felt252, target: u64, deadline: u64, description: felt252);

    /// Retrieve contract balance.
    fn pledge(ref self: TContractState, name: felt252, amount: u64);

    // A pledger changes his mind
    fn unpledge(ref self: TContractState, name: felt252, amount: u64);

    //Refund contributors if the target is not met
    fn refund(ref self: TContractState, name: felt252);


    // withdraw contribution after target are met
    fn withdraw(ref self: TContractState, name: felt252, amount: u64, recipient: ContractAddress) -> bool;

    //view campaign progress
    fn viewProgress(self: @TContractState, name: felt252) -> campaign ;

}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct campaign {
     creator: ContractAddress,
     id: u64,
     target: u64,
     start_balance: u64,
     start_at: u64,
     deadline: u64,
     description: felt252,
     claimed: bool,
    }


#[starknet::contract]
mod Helpnet {
    use starknet::storage::{Map};
    use starknet::ContractAddress;
    use super::{get_caller_address, get_block_timestamp};
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry};
    use super::campaign;


   #[storage]
   struct Storage {
     id: u64,
     Current_balance: u64,
     name_id: Map<felt252, u64>,   
     campaigns: Map<u64, campaign>,
     campaign_by_name: Map<felt252, campaign>,
     balances: Map<ContractAddress, u64>,
     num_campaigns: u64,
   }

//    // A typical campaign type
//    #[derive(Drop, Copy, Serde)]
//    pub struct campaign {
//     creator: ContractAddress,
//     id: u64,
//     target: u64,
//     start_balance: u64,
//     start_at: u64,
//     deadline: u64,
//     description: felt252,
//     claimed: bool,
//    }

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
        target: u64,
        start_balance: u64,
        start_at: u64,
        deadline: u64,
        id: u64,
        description: felt252,
   }

   #[derive(Drop, starknet::Event)]
   pub struct place_pledge {
     name: felt252,
     pledger: ContractAddress,
     amount: u64,
     balance: u64,
   }

#[derive(Drop, starknet::Event)]
pub struct un_pledge {
     name: felt252,
     pledger: ContractAddress,
     amount: u64,
     balance: u64,
}

#[derive(Drop, starknet::Event)]
pub struct re_fund {
     name: felt252,
     amount: u64,
     balance: u64,
}

#[derive(Drop, starknet::Event)]
pub struct fund_withdraw{
     name: felt252,
     amount: u64,
     from: ContractAddress,
     to: ContractAddress,
}

   #[abi(embed_v0)]
   impl HelpnetImpl of super::IHelpnet<ContractState> {

    fn create_campaign(ref self: ContractState, start_balance: u64, name: felt252, target: u64, deadline: u64, description: felt252) {

     let start_at: u64 = get_block_timestamp();
     let _deadline: u64 = start_at + deadline;
     let creator = get_caller_address();

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
               claimed: false,
          };

          self.campaigns.entry(updated_id).write(_new_campaign);

          self.campaign_by_name.entry(name).write(_new_campaign);

         self.num_campaigns.write(self.num_campaigns.read() + 1);

         self.balances.entry(creator).write(start_balance);

         self.Current_balance.write(self.Current_balance.read() + start_balance);

         self.emit(createCampaign { creator: creator,
          target: target,
          start_balance: start_balance,
          start_at: start_at,
          deadline: deadline,
          id: updated_id,
          description: description, });

    }

    /// Retrieve contract balance.
   fn pledge(ref self: ContractState, name: felt252, amount: u64) {


      let _campaign: campaign = self.campaign_by_name.entry(name).read();
 
      let current_time = get_block_timestamp();

          assert(current_time < _campaign.deadline, 'Campaign ended');
          assert(current_time >=  _campaign.start_at, 'Campaign not started');

          // updating the balance
          self.Current_balance.write(self.Current_balance.read() + amount);
          let updated_balance: u64 = self.Current_balance.read();

          //keeping track of users and their pledges
          self.balances.entry(get_caller_address()).write(amount);

          self.emit(place_pledge {  name: name,
               amount: amount,
               pledger: get_caller_address(),
               balance: updated_balance,});
    }
   

    // A pledger changes his mind
    fn unpledge(ref self: ContractState, name: felt252, amount: u64) {

     let _campaign: campaign = self.campaign_by_name.entry(name).read();

     let current_time = get_block_timestamp();

     let pledger_balance = self.balances.entry(get_caller_address()).read();   

          assert(pledger_balance >= amount, 'Insufficient funds');
          assert(current_time < _campaign.deadline, 'Campaign ended');

    
      // updating the balance
      self.Current_balance.write(self.Current_balance.read() - amount);
      let updated_balance: u64 = self.Current_balance.read();

      self.emit(un_pledge {  name: name,
          amount: amount,
          pledger: get_caller_address(),
          balance: updated_balance,});
        
    }

    // withdraw contribution after target are met
    fn withdraw(ref self: ContractState, name: felt252, amount: u64, recipient: ContractAddress ) -> bool {
      
     let _campaign: campaign = self.campaign_by_name.entry(name).read();
     let current_time = get_block_timestamp();
     let creator_address = _campaign.creator;  
     let withdrawer = get_caller_address(); 

     

     assert(creator_address == withdrawer, 'Not the creator');
     assert(current_time >= _campaign.deadline, 'Campaign is not ended');

     let _creator_amount = self.balances.entry(creator_address).read();
     let _recipient_amount = self.balances.entry(recipient).read();

     let current_amount = _creator_amount - amount;

     self.Current_balance.write(self.Current_balance.read() - amount);

    // self.balances.entry(recipient).write(self.balances.);
     self.balances.entry(creator_address).write(current_amount);
     
     self.balances.entry(recipient).write(_recipient_amount + amount);

     self.Current_balance.write(self.Current_balance.read() - amount);

     self.emit(fund_withdraw {
          name: name,
          amount: amount,
          from: _campaign.creator,
          to: recipient,
     });

     _campaign.claimed;
     true

    }


    //Refund contributors if the target is not met
    fn refund(ref self: ContractState, name: felt252) {
          

    }

    //view campaign progress
//     fn viewProgress(self: @TContractState, name: ByteArray) -> campaign {
     

//      let campaign = new_campaign {
//           creator: _campaign.creator(),
//           id: _campaign.id(),
//           target: _campaign.target(),
//           start_balance: _campaign,
//           start_at: u64,
//           deadline: u64,
//           description: ByteArray,
//           claimed: bool,
//      }
//     }

    fn viewProgress(self: @ContractState, name: felt252) -> campaign {
     let _campaign: campaign = self.campaign_by_name.entry(name).read();

     let current_time = get_block_timestamp();

     assert(current_time <= _campaign.deadline(), "Campaign ended");

     // creator: ContractAddress,
     // id: u64,
     // target: u64,
     // start_balance: u64,
     // start_at: u64,
     // deadline: u64,
     // description: ByteArray,
     // claimed: bool,

     return  campaign {
          creator: _campaign.creator,
         id:  _campaign.id,
          target:_campaign.target,
          start_balance: _campaign.start_balance,
          start_at:_campaign.start_at,
          deadline:  _campaign.deadline,
          description:  _campaign.description,
          claimed:  _campaign._campaign,
     };
    }


   


   }





}