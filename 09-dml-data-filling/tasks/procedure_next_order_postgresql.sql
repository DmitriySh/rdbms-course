-- procedure with transaction: use PostgreSQL 11+
-- the procedure to make an order to buy a product in an e-commerce store
-- affect to tables `otus.order`, `otus.order_log`, `otus.order_details`

CREATE OR REPLACE PROCEDURE next_store_order(VARCHAR(512), INT, VARCHAR(50)) AS
$$
DECLARE
    _product_name ALIAS FOR $1;
    _order_product_count ALIAS FOR $2;
    _client_email ALIAS FOR $3;
    _schedule_interval interval = '3 day';
    _product_id        BIGINT;
    _client_id         BIGINT;
    _order_id          BIGINT;
    _product_price     NUMERIC;
    _not_paid_orders   INT;
    _scheduled_time    TIMESTAMPTZ;
    _created_time      TIMESTAMPTZ;
BEGIN
    _created_time := now();
    _scheduled_time := _created_time + _schedule_interval;

    -- select product id
    _product_id := (select p.id
                    from otus.product as p
                    where p.description = _product_name
                      and p.count >= _order_product_count FOR UPDATE);
    IF (_product_id IS NULL OR _product_id = 0) THEN
        RAISE EXCEPTION 'product % or required product quantity not found', _product_name;
    END IF;

    -- select product price
    _product_price := (SELECT p.price FROM otus.product_price as p WHERE p.product_id = _product_id);
    IF (_product_price IS NULL OR _product_price = 0.0) THEN
        RAISE EXCEPTION 'price for product % not found', _product_id;
    END IF;

    -- select client account id
    _client_id := (SELECT a.id
                   FROM otus.account AS a
                   WHERE a.email = _client_email
                     AND a.type = 'client'
                     AND a.deleted = false);
    IF (_client_id IS NULL OR _client_id = 0) THEN
        RAISE EXCEPTION 'available client account % not found', _client_email;
    END IF;

    -- book products
    UPDATE otus.product SET count = (count - _order_product_count), updated_time = _created_time WHERE id = _product_id;

    -- make a new order
    INSERT INTO otus.order (owner_id, product_id, status, address, created_time, scheduled_time)
    VALUES (_client_id, _product_id, 'not_paid', 'address', _created_time, _scheduled_time) RETURNING id INTO _order_id;

    INSERT INTO otus.order_details (order_id, product_id, comment, count, total_price, created_time)
    VALUES (_order_id, _product_id, 'comment', _order_product_count, (_product_price * _order_product_count),
            _created_time);

    INSERT INTO otus.order_log (order_id, modified_by, count, status, created_time, scheduled_time)
    VALUES (_order_id, _client_id, _order_product_count, 'not_paid', _created_time, _scheduled_time);

    -- test not paid orders
    _not_paid_orders := (SELECT count(1)
                         FROM otus.order AS o
                         WHERE o.owner_id = _client_id
                           AND o.product_id = _product_id
                           AND o.status = 'not_paid');

    IF (_not_paid_orders > 1) THEN
        ROLLBACK;
        RAISE NOTICE '%', 'product_id = ' || _product_id || ', name = ' || _product_name || ' for account_id = ' ||
                          _client_id || ', e-mail = ' || _client_email
            || '; product already ordered but not paid, please cancel order or increase the count of products in order';
    ELSE
        COMMIT;
        RAISE NOTICE '%', 'product_id = ' || _product_id || ', name = ' || _product_name;
        RAISE NOTICE 'product_price = %', _product_price;
        RAISE NOTICE '%', 'account_id = ' || _client_id || ', e-mail = ' || _client_email;
        RAISE NOTICE 'schedule_interval = %', _schedule_interval;
        RAISE NOTICE 'order_id = %, status = not_paid', _order_id;
    END IF;

END;
$$ LANGUAGE plpgsql;
