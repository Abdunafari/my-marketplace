/*
/// Module: m_marketplace
module m_marketplace::m_marketplace;
*/


module m_marketplace::m_marketplace {
    use sui::dynamic_field as ofield;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::bag::{Bag, Self};
    use sui::table::{Table, Self};
    use sui::transfer;


    // for when acount paid does not match the expected
    const EAmountIncorrect: u64 = 0;
    // for when someone tries to delist without ownership
    const ENotOwner: u64 = 1;

    // A shared 'marketplace' can be created by anyone using the
    // create function. one instance of 'marketplace' accepts only
    //type of COin 'Coin' for all its listening

    public struct Marketplace<phantom COIN> has key {
        id: UID,
        items: Bag,
        payments: Table<address, Coin<COIN>>

    }

    // A single listing which contains the listed item and its
    //price in ['coin<coin>']

    public struct Listing has key, store {
        id: UID,
        ask: u64,
        owner: address,
    }

    // create a new marketplace
    public fun create<COIN>(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let items = bag::new(ctx);
        let payments = table::new<address, Coin<COIN>>(ctx);
        transfer::share_object(Marketplace<COIN> {
            id,
            items,
            payments
        })
    }

    // list an item at the marketplace
    public fun list<T: key + store, COIN>(
        m_marketplace: &mut Marketplace<COIN>,
        item: T,
        ask: u64,
        ctx: &mut TxContext
    ) {
        let item_id = object::id(&item);
        let mut listing = Listing {
            ask,
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
        };

        ofield::add(&mut listing.id, true, item);
        bag::add(&mut m_marketplace.items, item_id, listing)
    }

    // Internal function to romve listing and get an item
    // back. only ownre can do that

    fun delist<T: key + store, COIN>(
        m_marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        ctx: &TxContext
    ): T {
        let Listing {
            mut id,
            owner,
            ask,

        } = bag::remove(&mut m_marketplace.items, item_id);

        assert!(tx_context::sender(ctx) == owner, ENotOwner);

        let item = ofield::remove(&mut id, true);
        object::delete(id);
        item
    }

    // call ['delist'] and transfer item to the sender
    public fun delist_and_take<T: key + store, COIN>(
        m_marketplace: &mut Marketplace<COIN>, 
        item_id: ID,
        ctx: &mut TxContext
    ) {
        let item = delist<T, COIN>(m_marketplace, item_id, ctx);
        transfer::public_transfer(item,tx_context::sender(ctx));
    }

    // internal function to purchase an item using a kwown listing, payment is done with a coin<c>
    // amount paid must match the request amount. if conditions are met,
    // owner of the itme gets the payment and buyer recieves their item.

    fun buy<T: key + store, COIN>(
        m_marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        paid: Coin<COIN>,
    ): T {
        let Listing {
            mut id,
            ask,
            owner
        } = bag::remove(&mut m_marketplace.items, item_id);

        assert!(ask == coin::value(&paid), EAmountIncorrect);

        // check if there is already a coin hanging and merge 'paid' with it.
        // otherwise attach 'paid' to the marketplace under owners 'address'

        if (table::contains<address, Coin<COIN>>(&m_marketplace.payments, owner)) {
            coin::join(
                table::borrow_mut<address, Coin<COIN>>(&mut m_marketplace.payments, owner),
                paid
                )
            
                
        } else {
            table::add(&mut m_marketplace.payments, owner, paid)

        };

        let item = ofield::remove(&mut id, true);
        object::delete(id);
        item

    }

    // call ['buy'] and transfer item to the sender
    public fun buy_and_take<T: key + store, COIN>(
        m_marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        paid: Coin<COIN>,
        ctx: &mut TxContext

    ) {
        transfer::public_transfer(
            buy<T, COIN>(m_marketplace, item_id, paid),
            tx_context::sender(ctx)
        )
    }


    // internal function to take profit from selling items on the marketplace

    fun take_profit<COIN>(
        m_marketplace: &mut Marketplace<COIN>,
        ctx: &TxContext

    ): Coin<COIN> {
        table::remove<address, Coin<COIN>>(&mut m_marketplace.payments, tx_context::sender(ctx))
    }

    #[lint_allow(self_transfer)]
    // call ['take_profit] and transfer Coin object to the sender

    public fun take_profits_and_keep<COIN>(
        m_marketplace: &mut Marketplace<COIN>,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(
            take_profit(m_marketplace, ctx),
            tx_context::sender(ctx)
            )
    }

}