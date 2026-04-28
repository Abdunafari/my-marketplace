#[test_only]
module m_marketplace::job_marketplace_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string::{Self};
    use m_marketplace::job_marketplace::{Self, JobMarketplace, FreelancerProfile, Gig, WorkContract, Review, Message};

    const ADMIN: address = @0xAD;
    const FREELANCER: address = @0x123;
    const CLIENT: address = @0x456;

    #[test]
    fun test_job_marketplace_flow() {
        let mut scenario = test_scenario::begin(ADMIN);

        // 1. Register Freelancer
        test_scenario::next_tx(&mut scenario, FREELANCER);
        {
            job_marketplace::register_freelancer(
                string::utf8(b"Alice"),
                string::utf8(b"Full-stack Developer"),
                vector[string::utf8(b"Move"), string::utf8(b"Rust")],
                test_scenario::ctx(&mut scenario)
            );
        };

        // 2. Create Gig
        test_scenario::next_tx(&mut scenario, FREELANCER);
        {
            let profile = test_scenario::take_from_address<FreelancerProfile>(&scenario, FREELANCER);
            job_marketplace::create_gig(
                &profile,
                string::utf8(b"Sui Smart Contract Dev"),
                string::utf8(b"I will build your Move modules"),
                1000,
                test_scenario::ctx(&mut scenario)
            );
            test_scenario::return_to_address(FREELANCER, profile);
        };

        // 3. Client orders Gig
        test_scenario::next_tx(&mut scenario, CLIENT);
        {
            let gig = test_scenario::take_shared<Gig>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(&mut scenario));

            job_marketplace::order_gig(
                &gig,
                payment,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(gig);
        };

        // 4. Freelancer submits work
        test_scenario::next_tx(&mut scenario, FREELANCER);
        {
            let mut contract = test_scenario::take_shared<WorkContract<SUI>>(&scenario);
            job_marketplace::submit_work(&mut contract, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(contract);
        };

        // 5. Client approves work and payment is released
        test_scenario::next_tx(&mut scenario, CLIENT);
        {
            let mut contract = test_scenario::take_shared<WorkContract<SUI>>(&scenario);
            job_marketplace::approve_work(&mut contract, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(contract);
        };

        // 6. Verify Freelancer received payment
        test_scenario::next_tx(&mut scenario, FREELANCER);
        {
            let payment_coin = test_scenario::take_from_address<Coin<SUI>>(&scenario, FREELANCER);
            assert!(coin::value(&payment_coin) == 1000, 0);
            test_scenario::return_to_address(FREELANCER, payment_coin);
        };

        // 7. Client posts review
        test_scenario::next_tx(&mut scenario, CLIENT);
        {
            let contract = test_scenario::take_shared<WorkContract<SUI>>(&scenario);
            job_marketplace::post_review(
                &contract,
                5,
                string::utf8(b"Great work!"),
                test_scenario::ctx(&mut scenario)
            );
            test_scenario::return_shared(contract);
        };

        // 8. Freelancer sends message to Admin
        test_scenario::next_tx(&mut scenario, FREELANCER);
        {
            job_marketplace::send_message(
                ADMIN,
                string::utf8(b"Hello Admin, I have a question."),
                test_scenario::ctx(&mut scenario)
            );
        };

        // 9. Admin checks message
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let message = test_scenario::take_from_address<Message>(&scenario, ADMIN);
            test_scenario::return_to_address(ADMIN, message);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = m_marketplace::job_marketplace::ENotAuthorized)]
    fun test_unauthorized_gig_creation() {
        let mut scenario = test_scenario::begin(ADMIN);

        // Register Alice
        test_scenario::next_tx(&mut scenario, FREELANCER);
        job_marketplace::register_freelancer(
            string::utf8(b"Alice"),
            string::utf8(b"Dev"),
            vector[],
            test_scenario::ctx(&mut scenario)
        );

        // Bob tries to create a gig using Alice's profile
        let bob = @0xBOB;
        test_scenario::next_tx(&mut scenario, bob);
        {
            let profile = test_scenario::take_from_address<FreelancerProfile>(&scenario, FREELANCER);
            job_marketplace::create_gig(
                &profile,
                string::utf8(b"Fake Gig"),
                string::utf8(b"Should fail"),
                1000,
                test_scenario::ctx(&mut scenario)
            );
            test_scenario::return_to_address(FREELANCER, profile);
        };

        test_scenario::end(scenario);
    }
}
