<?php
require 'src/bootstrap.php';
$q = db()->query(
    'SELECT id, (SELECT count(*) FROM notifications n WHERE n.capsule_id = c.id)
     AS notifications FROM capsules c WHERE id IN (6, 7, 8, 9) ORDER BY id'
);
foreach ($q as $row) {
    echo 'capsule ', $row['id'], ': notifications=', $row['notifications'], "\n";
}
