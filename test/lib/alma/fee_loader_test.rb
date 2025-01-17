require 'test_helper'

class Alma::FeeLoaderTest < ActiveSupport::TestCase

  # NOT TESTING GETTING FEES, as it is part of the alma gem and tested there.

  FEE_SAMPLE = { "id" => "12345678910",
                 "type" => { "value" => "OVERDUEFINE", "desc" => "Overdue fine" },
                 "status" => { "value" => "ACTIVE", "desc" => "Active" },
                 "user_primary_id" => { "value" => "12345678910", "link" => "https://something.com" },
                 "balance" => 3.0,
                 "remaining_vat_amount" => 0.0,
                 "original_amount" => 3.0,
                 "original_vat_amount" => 0.0,
                 "creation_time" => "2010-10-27T10:59:00Z",
                 "status_time" => "2019-05-30T02:01:11Z",
                 "comment" => "CALL_ITEMNUM: QP 355.2 P76 2000 | ITEM_COPYNUM: 4 | USER_ALT_ID: 123456789",
                 "owner" => { "value" => "SCOTT", "desc" => "Scott Library" },
                 "title" => "Principles of neural science / edited by Eric R. Kandel, James H. Schwartz, Thomas M. Jessell ; art direction by Sarah Mack and Jane Dodd.",
                 "barcode" => { "value" => "39007047016860", "link" => "https://something.com" },
                 "link" => "https://something.com"
                }

  should "parse alma json fees into Alma::Fee objects" do
    yorku_id = "10101010"
    local_user = create :user, yorku_id: yorku_id, username: "12345678910"
    fee = Alma::FeeLoader.parse_alma_fee FEE_SAMPLE, local_user

    assert_equal fee.yorku_id, local_user.yorku_id
    assert_equal fee.user_primary_id, local_user.username

    assert_equal fee.fee_id, FEE_SAMPLE["id"]
    assert_equal fee.fee_type, FEE_SAMPLE["type"]["value"]
    assert_equal fee.fee_description,FEE_SAMPLE["type"]["desc"]
    assert_equal fee.fee_status, FEE_SAMPLE["status"]["value"]

    assert_equal fee.user_primary_id, FEE_SAMPLE["user_primary_id"]["value"]

    assert_equal fee.balance, FEE_SAMPLE["balance"]
    assert_equal fee.remaining_vat_amount, FEE_SAMPLE["remaining_vat_amount"]
    assert_equal fee.original_amount, FEE_SAMPLE["original_amount"]
    assert_equal fee.original_vat_amount, FEE_SAMPLE["original_vat_amount"]
    assert_equal fee.creation_time, Time.zone.parse(FEE_SAMPLE["creation_time"])
    assert_equal fee.status_time, Time.zone.parse(FEE_SAMPLE["status_time"])

    assert_equal fee.owner_id, FEE_SAMPLE["owner"]["value"]
    assert_equal fee.owner_description, FEE_SAMPLE["owner"]["desc"]

    assert_equal fee.item_title, FEE_SAMPLE["title"]
    assert_equal fee.item_barcode, FEE_SAMPLE["barcode"]["value"]
  end

  should "create a brand new fee since it doesn't exist" do
    yorku_id = 101010
    local_user = create :user, yorku_id: yorku_id
    assert_difference "Alma::Fee.count" do
      alma_fee = Alma::FeeLoader.parse_alma_fee FEE_SAMPLE, local_user
      Alma::FeeLoader.update_existing_or_create_new alma_fee, local_user
    end

    assert_equal 1, Alma::Fee.active.size, "Ensure that there is one active fee"
  end

  should "update existing fee, if it exists" do
    yorku_id = 101010
    local_user = create :user, yorku_id: yorku_id
    alma_fee = Alma::FeeLoader.parse_alma_fee FEE_SAMPLE, local_user
    updated = Alma::FeeLoader.update_existing_or_create_new alma_fee, local_user

    changed_fee = FEE_SAMPLE.clone
    changed_fee["balance"] = 10.0

    assert updated.balance == FEE_SAMPLE["balance"]

    assert_no_difference "Alma::Fee.count" do
      alma_fee2 = Alma::FeeLoader.parse_alma_fee changed_fee, local_user
      new_one = Alma::FeeLoader.update_existing_or_create_new alma_fee2, local_user

      assert new_one.balance == changed_fee["balance"]
    end

    assert_equal 1, Alma::Fee.active.size, "Ensure that there is one active fee"
  end

  should "only change predefined fees" do
    yorku_id = 101010
    local_user = create :user, yorku_id: yorku_id
    alma_fee = Alma::FeeLoader.parse_alma_fee FEE_SAMPLE, local_user
    updated = Alma::FeeLoader.update_existing_or_create_new alma_fee, local_user

    changed_fee = FEE_SAMPLE.clone
    changed_fee["balance"] = 10.0
    changed_fee["remaining_vat_amount"] = 10.0
    changed_fee["status_time"] = "2019-06-30T02:01:11Z"
    changed_fee["status"]["value"] = "DIFFERENTONE"

    changed_fee["original_amount"] = 202020.0
    changed_fee["creation_time_time"] = "2019-06-30T02:01:11Z"
    changed_fee["title"] = "TITLE CHANGE"

    assert updated.balance == FEE_SAMPLE["balance"]
    assert updated.original_amount == FEE_SAMPLE["original_amount"]

    alma_fee2 = Alma::FeeLoader.parse_alma_fee changed_fee, local_user
    new_one = Alma::FeeLoader.update_existing_or_create_new alma_fee2, local_user

    assert_equal 1, Alma::Fee.active.size, "Ensure that there is one active fee"

    assert new_one.balance == changed_fee["balance"]
    assert new_one.remaining_vat_amount == changed_fee["remaining_vat_amount"]
    assert new_one.status_time == Time.zone.parse(changed_fee["status_time"])
    assert new_one.fee_status == changed_fee["status"]["value"]

    assert new_one.original_amount == FEE_SAMPLE["original_amount"]
    assert new_one.creation_time == FEE_SAMPLE["creation_time"]
    assert new_one.item_title == FEE_SAMPLE["title"]
  end

  should "get values out of the HASH ## HELPER METHOD" do
    assert_equal FEE_SAMPLE["status"]["value"], Alma::FeeLoader.get_val(FEE_SAMPLE, :status, :value)

    assert_equal FEE_SAMPLE["balance"], Alma::FeeLoader.get_val(FEE_SAMPLE, :balance)

    assert_equal "n/a", Alma::FeeLoader.get_val(FEE_SAMPLE, :something_else, :value)
    assert_nil Alma::FeeLoader.get_val(FEE_SAMPLE, :something_else)
  end

  should "mark all active fees as stale for user" do
    yorku_id = 101010
    local_user = create :user, yorku_id: yorku_id

    #alma_fee = Alma::FeeLoader.parse_alma_fee FEE_SAMPLE, local_user
    create :alma_fee, fee_status: "ACTIVE", yorku_id: local_user.yorku_id, user_primary_id: local_user.username
    create :alma_fee, fee_status: "ACTIVE", yorku_id: "SOMETHING_ELSE", user_primary_id: "something else"
    create :alma_fee, fee_status: Alma::Fee::STATUS_STALE, yorku_id: yorku_id, user_primary_id: local_user.username
    create :alma_fee, fee_status: Alma::Fee::STATUS_PAID, yorku_id: yorku_id, user_primary_id: local_user.username

    assert_equal 1, local_user.alma_fees.size

    Alma::FeeLoader.mark_all_active_fees_as_stale local_user

    assert_equal 0, local_user.alma_fees.size
  end

  should "get test user from Alma" do
    if Settings.alma.test_user_primary_id
      VCR.use_cassette('get_test_user_from_alma') do
        alma_test_user = Alma::User.find Settings.alma.test_user_primary_id
        assert_equal Settings.alma.test_user_primary_id, alma_test_user.primary_id
      end
    end
  end

  should "get test user fees from Alma" do
    alma_test_user = nil

    if Settings.alma.test_user_primary_id
      VCR.use_cassette('get_test_user_from_alma') do
        alma_test_user = Alma::User.find Settings.alma.test_user_primary_id
        assert_equal Settings.alma.test_user_primary_id, alma_test_user.primary_id
      end
      
      VCR.use_cassette('get_test_user_fees_from_alma') do
        fees = alma_test_user.fines.response["fee"] if alma_test_user
        assert_equal 4, fees.size
      end
    end
  end

  should "parse REAL Alma json fees into Alma::Fee objects" do
    if Settings.alma.test_user_primary_id
      fee_count_before = Alma::Fee.count

      alma_test_user = nil

      VCR.use_cassette('get_test_user_from_alma') do
        alma_test_user = Alma::User.find Settings.alma.test_user_primary_id if Settings.alma.test_user_primary_id
        assert_equal Settings.alma.test_user_primary_id, alma_test_user.primary_id
      end

      alma_test_user_fees = nil
      VCR.use_cassette('get_test_user_fees_from_alma') do
        alma_test_user_fees = alma_test_user.fines.response["fee"] if alma_test_user
        assert_equal 4, alma_test_user_fees.size
      end

      univ_id = User.get_univ_id_from_alma_user(alma_test_user)
      local_user = create :user, yorku_id: univ_id, username: alma_test_user.primary_id
      alma_test_user_fees.each do |f|
        fee = Alma::FeeLoader.parse_alma_fee f, local_user
        assert fee.save

        assert_equal fee.yorku_id, local_user.yorku_id
        assert_equal fee.user_primary_id, local_user.username

        assert_equal fee.fee_id, f["id"]
        assert_equal fee.fee_type, f["type"]["value"]
        assert_equal fee.fee_description, f["type"]["desc"]
        assert_equal fee.fee_status, f["status"]["value"]
        assert_equal fee.user_primary_id, f["user_primary_id"]["value"]
        assert_equal fee.balance, f["balance"]
        assert_equal fee.remaining_vat_amount, f["remaining_vat_amount"]
        assert_equal fee.original_amount, f["original_amount"]
        assert_equal fee.original_vat_amount, f["original_vat_amount"]
        assert_equal fee.creation_time, Time.zone.parse(f["creation_time"])
        assert_equal fee.status_time, Time.zone.parse(f["status_time"])
        assert_equal fee.owner_id, f["owner"]["value"]
        assert_equal fee.owner_description, f["owner"]["desc"]
        assert_equal fee.item_title, f["title"]
        assert_equal fee.item_barcode, f["barcode"]["value"]
      end

      fee_count_after = Alma::Fee.count
      assert_equal fee_count_after, fee_count_before + alma_test_user_fees.size
    end
  end
end
