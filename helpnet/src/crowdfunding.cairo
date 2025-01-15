use starknet::{ContractAddress, get_caller_address, get_block_timestamp};

#[starknet::interface]
pub trait IHelpnet<TContractState> {
    // create campaign
    fn create_campaign(ref self: TContractState, start_balance: u64, name: ByteArray, target: u64, deadline: u64, description: ByteArray);

    /// Retrieve contract balance.
    fn pledge(ref self: TContractState, name: ByteArray, amount: u64);

    // A pledger changes his mind
    fn unpledge(ref self: TContractState, name: ByteArray, amount: u64);

    //Refund contributors if the target is not met
    fn refund(ref self: TContractState, name: ByteArray);


    // withdraw contribution after target are met
    fn withdraw(ref self: TContractState, name: ByteArray, amount: u64) -> bool;

    //view campaign progress
    fn viewProgress(self: @TContractState, name: ByteArray) -> (creator: ContractAddress, current_balance: u64, target: u64, deadline: u64);

}


#[starknet::contract]
mod Helpnet {
    use starknet::storage::{Map};
    use starknet::ContractAddress;
    use super::{get_caller_address, get_block_timestamp};
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};


   #[storage]
   struct Storage {
     id: u64,
     Current_balance: u64,
     name_id: Map<name: ByteArray, u64>,   
     campaigns: Map<u64, campaign>,
     campaign_by_name: Map<name: ByteArray, campaign>,
     balances: Map<ContractAddress, u64>,
     num_campaigns: u64,
   }

   // A typical campaign type
   pub struct campaign {
    creator: ContractAddress,
    id: u64,
    target: u64,
    start_balance: u64,
    start_at: u64,
    deadline: u64,
    description: ByteArray,
    claimed: bool,
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
        target: u64,
        start_balance: u64,
        start_at: u64,
        deadline: u64,
        id: u64,
        description: ByteArray,
   }

   #[derive(Drop, starknet::Event)]
   pub struct place_pledge {
     name: String,
     pledger: ContractAddress,
     amount: u64,
     balance: u64,
   }

#[derive(Drop, starknet::Event)]
pub struct un_pledge {
     name: String,
     pledger: ContractAddress,
     amount: u64,
     balance: u64,
}

#[derive(Drop, starknet::Event)]
pub struct re_fund {
     name: String,
     amount: u64,
     balance: u64,
}

#[derive(Drop, starknet::Event)]
pub struct fund_withdraw{
     name: String,
     amount: u64,
     from: ContractAddress,
     to: ContractAddress,
}

   #[abi(embed_v0)]
   impl HelpnetImpl of super::IHelpnet<ContractState> {

    fn create_campaign(ref self: ContractState, start_balance: u64, name: String, target: u64, deadline: u64, description: ByteArray) {

     let start_at: u64 = get_block_timestamp();
     let _deadline: u64 = start_at + deadline;
     let creator = get_caller_address();

     let current_id = self.id.read();
     updated_id = current_id + 1;

     assert(deadline > 0, "invalid duration");

     self.name_id.entry(name).write(updated_id);
   
     self.current_balance.write(current_balance + start_balance);

          
          let new_campaign = campaign {
               creator: creator,
               target: target,
               start_balance: u64,
               start_at: start_at,
               deadline: _deadline,
               description: description,
          }

          self.campaigns.write(updated_id, new_campaign);

          self.campaign_by_name.write(name, new_campaign);

         self.num_campaigns.write(num_campaigns + 1);

         self.balances.entry(creator).write(start_balance);

         self.current_balance.write(current_balance + start_balance);

         self.emit(createCampaign { creator: creator,
          target: target,
          start_balance: start_balance,
          start_at: start_at,
          deadline: deadline,
          id: updated_id,
          description: description, });

    }

    /// Retrieve contract balance.
   fn pledge(ref self: ContractState, name: ByteArray, amount: u64) {


      let _campaign: campaign = self.campaign_by_name.entry(name).read();
 
      let current_time = get_block_timestamp();

      let pledger_balance = self.balances.entry(get_caller_address()).read();   

          assert(pledger_balance >= amount, "Insufficient funds");
          assert(current_time < _campaign.deadline(), "Campaign ended");
          assert(current_time >=  _campaign.start_at(), "Campaign not started");

          // updating the balance
          self.Current_balances.write(Current_balance + amount);
          let updated_balance: u64 = self.Current_balances.read();

          //keeping track of users and their pledges
          self.balances.entry(get_caller_address()).write(amount);

          self.emit(place_pledge {  name: name,
               amount: amount,
               pledger: get_caller_address(),
               balance: updated_balance,});
    }
   

    // A pledger changes his mind
    fn unpledge(ref self: ContractState, name: ByteArray, amount: u64) {

     let _campaign: campaign = self.campaign_by_name.entry(name).read();

     let current_time = get_block_timestamp();

     let pledger_balance = self.balances.entry(get_caller_address()).read();   

          assert(pledger_balance >= amount, "Insufficient funds");
          assert(current_time < _campaign.deadline(), "Campaign ended");

    
      // updating the balance
      self.Current_balance.write(Current_balance - amount);
      let updated_balance: u64 = self.Current_balance.read();

      self.emit(un_pledge {  name: name,
          amount: amount,
          pledger: get_caller_address(),
          balance: updated_balance,});
        
    }

    // withdraw contribution after target are met
    fn withdraw(ref self: ContractState, name: ByteArray, amount: u64, recipient: ContractAddress ) -> bool {
      
     let _campaign: campaign = self.campaign_by_name.entry(name).read();
     let current_time = get_block_timestamp();
     let creator_balance = self.balances.entry(get_caller_address()).read();  
     let withdrawer = get_caller_address(); 
     let recipient_balance = self.balances.entry(recipient).read();

     assert(creator_balance = _campaign.creator(), "Not the creator");
     assert(current_time >= _campaign.deadline, "Campaign is not ended");
     assert(withdrawer = _campaign.creator(), "Withdrawer is not creator");  

     self.balances.entry(sender).write(sender_balance - amount);
     self.balances.entry(recipient).write(recipient_balance + amount);

     self.Current_balance.write(Current_balance - amount);

     self.emit(fund_withdraw {
          name: name,
          amount: amount,
          from: _campaign.creator(),
          to: recipient,
     });

     _campaign.claimed

    }


    //Refund contributors if the target is not met
    fn refund(ref self: ContractState, name: ByteArray) {

    }

    //view campaign progress
    fn viewProgress(self: @TContractState, name: ByteArray) -> campaign {
     let _campaign: campaign = self.campaign_by_name.entry(name).read();

     let current_time = get_block_timestamp();

     assert(current_time <= _campaign.deadline(), "Campaign ended");

     let campaign = new_campaign {
          creator: _campaign.creator(),
          id: _campaign.id(),
          target: _campaign.target(),
          start_balance: _campaign,
          start_at: u64,
          deadline: u64,
          description: ByteArray,
          claimed: bool,
     }




      campaign {
          creator: ContractAddress,
          id: u64,
          target: u64,
          start_balance: u64,
          start_at: u64,
          deadline: u64,
          description: ByteArray,
          claimed: bool,
         }


    }

   


   }





}