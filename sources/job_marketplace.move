module m_marketplace::job_marketplace {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::event;
    use std::string::String;

    // Error codes
    const EAmountIncorrect: u64 = 0;
    const EInvalidStatus: u64 = 1;
    const ENotAuthorized: u64 = 2;
    const EGigNotActive: u64 = 3;
    const EInvalidRating: u64 = 4;

    // Work contract status
    const STATUS_ORDERED: u8 = 0;
    const STATUS_SUBMITTED: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_DISPUTED: u8 = 3;

    public struct JobMarketplace has key {
        id: UID,
        admin: address,
    }

    // This is a helper for admin to view specific freelancer data off-chain
    // In Move, we often rely on events and object ownership for "views".
    // But we can add explicit functions that admin can call if needed.

    public struct FreelancerProfile has key, store {
        id: UID,
        freelancer: address,
        name: String,
        bio: String,
        skills: vector<String>,
    }

    public struct Gig has key, store {
        id: UID,
        freelancer: address,
        title: String,
        description: String,
        price: u64,
        active: bool,
    }

    public struct WorkContract<phantom COIN> has key {
        id: UID,
        gig_id: ID,
        freelancer: address,
        client: address,
        escrow: Balance<COIN>,
        status: u8,
    }

    public struct Review has key, store {
        id: UID,
        contract_id: ID,
        freelancer: address,
        rating: u8,
        comment: String,
    }

    public struct Message has key, store {
        id: UID,
        sender: address,
        receiver: address,
        content: String,
    }

    // Events
    public struct FreelancerRegistered has copy, drop {
        freelancer_id: ID,
        freelancer_address: address,
    }

    public struct GigCreated has copy, drop {
        gig_id: ID,
        freelancer: address,
        price: u64,
    }

    public struct GigDeactivated has copy, drop {
        gig_id: ID,
    }

    public struct ContractCreated has copy, drop {
        contract_id: ID,
        gig_id: ID,
        client: address,
        freelancer: address,
    }

    public struct WorkSubmitted has copy, drop {
        contract_id: ID,
    }

    public struct WorkApproved has copy, drop {
        contract_id: ID,
    }

    public struct GigUpdated has copy, drop {
        gig_id: ID,
        price: u64,
    }

    public struct DisputeResolved has copy, drop {
        contract_id: ID,
        released_to_freelancer: bool,
    }

    public struct ReviewPosted has copy, drop {
        review_id: ID,
        contract_id: ID,
        freelancer: address,
        rating: u8,
    }

    public struct MessageSent has copy, drop {
        message_id: ID,
        sender: address,
        receiver: address,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(JobMarketplace {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
        });
    }

    public fun register_freelancer(
        name: String,
        bio: String,
        skills: vector<String>,
        ctx: &mut TxContext
    ) {
        let freelancer_address = tx_context::sender(ctx);
        let id = object::new(ctx);
        let profile = FreelancerProfile {
            id,
            freelancer: freelancer_address,
            name, bio, skills,
        };
        event::emit(FreelancerRegistered {
            freelancer_id: object::id(&profile),
            freelancer_address,
        });
        transfer::public_transfer(profile, freelancer_address);
    }

    public fun update_freelancer_profile(
        profile: &mut FreelancerProfile,
        name: String,
        bio: String,
        skills: vector<String>,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == profile.freelancer, ENotAuthorized);
        profile.name = name;
        profile.bio = bio;
        profile.skills = skills;
    }

    public fun create_gig(
        _profile: &FreelancerProfile,
        title: String,
        description: String,
        price: u64,
        ctx: &mut TxContext
    ) {
        let freelancer = tx_context::sender(ctx);
        assert!(freelancer == _profile.freelancer, ENotAuthorized);

        let id = object::new(ctx);
        let gig = Gig {
            id,
            freelancer,
            title,
            description,
            price,
            active: true,
        };
        event::emit(GigCreated {
            gig_id: object::id(&gig),
            freelancer,
            price,
        });
        transfer::public_share_object(gig);
    }

    public fun update_gig(
        gig: &mut Gig,
        title: String,
        description: String,
        price: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == gig.freelancer, ENotAuthorized);
        gig.title = title;
        gig.description = description;
        gig.price = price;
        event::emit(GigUpdated {
            gig_id: object::id(gig),
            price,
        });
    }

    public fun deactivate_gig(
        gig: &mut Gig,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == gig.freelancer, ENotAuthorized);
        gig.active = false;
        event::emit(GigDeactivated {
            gig_id: object::id(gig),
        });
    }

    public fun order_gig<COIN>(
        gig: &Gig,
        payment: Coin<COIN>,
        ctx: &mut TxContext
    ) {
        assert!(gig.active, EGigNotActive);
        assert!(coin::value(&payment) == gig.price, EAmountIncorrect);

        let client = tx_context::sender(ctx);
        let contract = WorkContract {
            id: object::new(ctx),
            gig_id: object::id(gig),
            freelancer: gig.freelancer,
            client,
            escrow: coin::into_balance(payment),
            status: STATUS_ORDERED,
        };

        event::emit(ContractCreated {
            contract_id: object::id(&contract),
            gig_id: object::id(gig),
            client,
            freelancer: gig.freelancer,
        });

        transfer::share_object(contract);
    }

    public fun submit_work<COIN>(
        contract: &mut WorkContract<COIN>,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == contract.freelancer, ENotAuthorized);
        assert!(contract.status == STATUS_ORDERED, EInvalidStatus);

        contract.status = STATUS_SUBMITTED;

        event::emit(WorkSubmitted {
            contract_id: object::id(contract),
        });
    }

    public fun post_review<COIN>(
        contract: &WorkContract<COIN>,
        rating: u8,
        comment: String,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == contract.client, ENotAuthorized);
        assert!(contract.status == STATUS_COMPLETED, EInvalidStatus);
        assert!(rating >= 1 && rating <= 5, EInvalidRating);

        let id = object::new(ctx);
        let review_id = object::uid_to_inner(&id);
        let review = Review {
            id,
            contract_id: object::id(contract),
            freelancer: contract.freelancer,
            rating,
            comment,
        };

        event::emit(ReviewPosted {
            review_id,
            contract_id: object::id(contract),
            freelancer: contract.freelancer,
            rating,
        });

        transfer::public_share_object(review);
    }

    public fun approve_work<COIN>(
        contract: &mut WorkContract<COIN>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == contract.client, ENotAuthorized);
        assert!(contract.status == STATUS_SUBMITTED, EInvalidStatus);

        contract.status = STATUS_COMPLETED;

        let amount = balance::value(&contract.escrow);
        let payment = coin::take(&mut contract.escrow, amount, ctx);
        transfer::public_transfer(payment, contract.freelancer);

        event::emit(WorkApproved {
            contract_id: object::id(contract),
        });
    }

    public fun dispute_work<COIN>(
        contract: &mut WorkContract<COIN>,
        ctx: &TxContext
    ) {
        assert!(
            tx_context::sender(ctx) == contract.client || tx_context::sender(ctx) == contract.freelancer,
            ENotAuthorized
        );
        contract.status = STATUS_DISPUTED;
    }

    public fun send_message(
        receiver: address,
        content: String,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let id = object::new(ctx);
        let message_id = object::uid_to_inner(&id);
        let message = Message {
            id,
            sender,
            receiver,
            content,
        };

        event::emit(MessageSent {
            message_id,
            sender,
            receiver,
        });

        transfer::public_transfer(message, receiver);
    }

    // Admin functions to "overlook" (these are mostly for documentation of intent,
    // as admin can already view shared objects and events off-chain)

    public fun get_admin_address(marketplace: &JobMarketplace): address {
        marketplace.admin
    }

    public fun resolve_dispute<COIN>(
        _marketplace: &JobMarketplace,
        contract: &mut WorkContract<COIN>,
        released_to_freelancer: bool,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == _marketplace.admin, ENotAuthorized);
        assert!(contract.status == STATUS_DISPUTED, EInvalidStatus);

        let amount = balance::value(&contract.escrow);
        let payment = coin::take(&mut contract.escrow, amount, ctx);

        if (released_to_freelancer) {
            transfer::public_transfer(payment, contract.freelancer);
        } else {
            transfer::public_transfer(payment, contract.client);
        };

        contract.status = STATUS_COMPLETED;

        event::emit(DisputeResolved {
            contract_id: object::id(contract),
            released_to_freelancer,
        });
    }
}
