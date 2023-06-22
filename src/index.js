const moment = require('moment')
const Joi = require('joi')

exports.handler = async () => {
    const object_with_date = { date: '2018-01-01T00:00:00.000Z' }
    const { error, value } = Joi.validate(object_with_date, { date: Joi.date().required() })

    if(error) {
        throw new Error(`Validation error: ${error.message}`)
    }

    return moment(object_with_date.date).format('MMMM Do YYYY, h:mm:ss a')
}
