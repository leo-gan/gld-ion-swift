func daysInMonth(_ year: Int, _ month: Int) -> Int {
    if month == 2 {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        return leap ? 29 : 28
    }
    if month == 4 || month == 6 || month == 9 || month == 11 { return 30 }
    return 31
}

func shiftDays(_ when: inout IonTime, _ days: Int) throws {
    var left = days
    while left > 0 {
        let dim = daysInMonth(when.year, when.month)
        let room = dim - when.day
        if left <= room {
            when.day += left
            return
        }
        left -= room + 1
        when.day = 1
        when.month += 1
        if when.month == 13 {
            when.month = 1
            when.year += 1
            if when.year > 999_999_999 {
                throw DecodeError(kind: DecodeError.kindRange, offset: 0)
            }
        }
    }
    while left < 0 {
        if when.day - 1 >= -left {
            when.day += left
            return
        }
        left += when.day
        when.month -= 1
        if when.month == 0 {
            when.month = 12
            when.year -= 1
            if when.year < 1 {
                throw DecodeError(kind: DecodeError.kindRange, offset: 0)
            }
        }
        when.day = daysInMonth(when.year, when.month)
    }
}

func applyOffset(_ when: inout IonTime, _ minutes: Int) throws {
    if when.prec < precMin { return }
    var total = when.hour * 60 + when.minute + minutes
    var days = 0
    while total < 0 {
        total += 1440
        days -= 1
    }
    while total >= 1440 {
        total -= 1440
        days += 1
    }
    when.hour = total / 60
    when.minute = total % 60
    if days != 0 { try shiftDays(&when, days) }
}
