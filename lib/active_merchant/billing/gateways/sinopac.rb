module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class SinopacGateway < Gateway
      self.test_url = "https://sandbox.sinopac.com/WebAPI/Service.svc/CreateATMorIBonTrans"
      self.live_url = "https://ecapi.sinopac.com/WebAPI/Service.svc/CreateATMorIBonTrans"

      self.supported_countries = ["TW"]
      self.default_currency = "TWD"
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = "https://ecapi.sinopac.com/"
      self.display_name = "SinoPac Gateway"

      STANDARD_ERROR_CODE_MAPPING = {}.freeze

      def initialize(options = {})
        requires!(options, :account, :transaction)
        @account = options.delete(:account)
        @key_num = Random.rand(3) + 1 # 隨機選擇 1 ~ 3 其中一組 KEY 作為加密用
        @transaction = options.delete(:transaction)
        @authenticate_digest = ""
        @tries = 10
        super
      end

      def purchase(money, payment, options = {})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit("sale", post)
      end

      def authorize(money, payment, options = {})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit("authonly", post)
      end

      # 【轉帳類】虛擬帳號訂單建立訊息規格
      def create_atm_or_ibon_trans
        reward_ids = @transaction.transaction_items.pluck(:reward_id)
        rewards = ProjectReward.where(id: reward_ids)
        title = rewards.pluck(:title).join("和").gsub(/[\p{Cntrl}\p{Punct}\p{Space}\p{S}\p{C}]/, "").truncate(60)

        order_no = @transaction.trade_no
        price = @transaction.money.to_i * 100 # 網易收以分為單位，100 代表 1 元
        currency = @transaction.transaction_items.first.reward_currency
        expire_date = 3.days.from_now.in_time_zone.strftime("%Y%m%d")
        payer_email = @transaction.user.email
        receiver_email = @transaction.recipient.contact_email
        param1 = @transaction.uuid
        param2 = @transaction.created_at
        param3 = ActiveMerchant::Billing::Base.mode

        api_url = test? ? test_url : live_url

        param_xml = <<-END.strip_heredoc
          <ATMOrIBonClientRequest xmlns="http://schemas.datacontract.org/2004/07/SinoPacWebAPI.Contract">
            <ShopNO>#{@account}</ShopNO>
            <KeyNum>#{@key_num}</KeyNum>
            <OrderNO>#{order_no}</OrderNO>
            <Amount>#{price}</Amount>
            <CurrencyID>#{currency}</CurrencyID>
            <ExpireDate>#{expire_date}</ExpireDate>
            <PayType>A</PayType>
            <PrdtName>#{title}</PrdtName>
            <PayerEmail>#{payer_email}</PayerEmail>
            <ReceiverEmail>#{receiver_email}</ReceiverEmail>
            <Param1>#{param1}</Param1>
            <Param2>#{param2}</Param2>
            <Param3>#{param3}</Param3>
          </ATMOrIBonClientRequest>
        END

        # response["SAMakeRPButtonClientResponse"]["PrdtURL"] # 收款鈕的連結網址
        # response["SAMakeRPButtonClientResponse"]["Status"] # S:處理成功(正常) F:處理失敗(錯誤)
        query(api_url, param_xml)
      end

      def capture(money, authorization, options = {})
        commit("capture", post)
      end

      def refund(money, authorization, options = {})
        commit("refund", post)
      end

      def void(authorization, options = {})
        commit("void", post)
      end

      def verify(credit_card, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private

      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_payment(post, payment)
      end

      def parse(body)
        {}
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(action, parameters)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response["some_avs_response_key"]),
          cvv_result: CVVResult.new(response["some_cvv_response_key"]),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
      end

      def message_from(response)
      end

      def authorization_from(response)
      end

      def post_data(action, parameters = {})
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end

      # 覆寫預設的 test? 方法，增加 :development 的判斷
      def test?
        mode = ActiveMerchant::Billing::Base.mode
        [:test, :development].include?(mode)
      end

      def query(url, param)
        headers = {
          "Content-Type" => %{text/xml;charset="utf-8"},
          "Authorization" => @authenticate_digest
        }
        # 第一次 POST 一定會失敗，要從伺服器回傳 header 中取出 token 加密後重新送出
        response = HTTParty.post(url, body: param, headers: headers)
        @transaction.update!(code_log: response.to_json)
        unless response.code.eql?(200)
          error_message = "Expected response to be a <200>, but was <#{response.code}>"
          raise HTTParty::ResponseError.new(response), error_message
        end
        response
      rescue HTTParty::ResponseError => e
        raise unless (@tries -= 1) > 0
        response = e.response
        @authenticate_digest = calculate_authenticate_header(response, param)
        sleep 1
        retry
      end

      def calculate_authenticate_header(response, param_xml)
        request = response.request
        key_datum = {
          1 => ENV["SINOPAC_API_KEY_DATA1"],
          2 => ENV["SINOPAC_API_KEY_DATA2"],
          3 => ENV["SINOPAC_API_KEY_DATA3"]
        }[@key_num]

        www_authenticate_digest_string = response.headers["WWW-Authenticate"][7..-1]
        www_authenticate_digest_params = www_authenticate_digest_string.split(", ").map do |item|
          item.scan(/(\w+)\="(.+)"/).flatten
        end.to_h

        realm = www_authenticate_digest_params["realm"]
        nonce = www_authenticate_digest_params["nonce"]
        qop = www_authenticate_digest_params["qop"]
        cnonce = Random.rand(123400..9999999)
        message = param_xml.gsub(/[\r\n\s]/, "") # message 雜湊運算前要把空白換行等符號全部濾掉
        api_url = request.uri
        method = request.http_method::METHOD # 取得 request 方法（"GET" 或 "POST"）

        ha1 = Digest::SHA256.hexdigest "#{@account}:#{realm}:#{key_datum}"
        ha2 = Digest::SHA256.hexdigest "#{method}:#{api_url}"
        verifycode = Digest::SHA256.hexdigest "#{ha1}:#{nonce}:#{cnonce}:#{qop}:#{message}:#{ha2}"

        %{Digest realm="#{realm}", nonce="#{nonce}", uri="#{api_url}", verifycode="#{verifycode}", qop=#{qop}, cnonce="#{cnonce}"}
      end
    end
  end
end
